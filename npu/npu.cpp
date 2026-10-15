// npu.cpp - the WiC64's matrix unit (see npu.h and docs/npu.md)

#include "npu.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstdio>
#include <utility>

namespace {

// The instructions
enum {
    OP_END = 0x00,
    OP_LOAD = 0x01,     // r rows cols fmt data...
    OP_STORE = 0x02,    // r fmt                       -> rows cols data...
    OP_FILL = 0x03,     // r rows cols k
    OP_IDENT = 0x04,    // r n
    OP_RANGE = 0x05,    // r rows cols start step
    OP_COPY = 0x06,     // d s
    OP_TRANSP = 0x07,   // d s
    OP_JOIN = 0x08,     // d a b how (0 side by side, 1 a above b)
    OP_FREE = 0x09,     // r
    OP_RESET = 0x0a,
    OP_DEFINE = 0x0b,   // s length(2) bytes...
    OP_RUN = 0x0c,      // s
    OP_CLOCK = 0x0d,    // r
    OP_ADD = 0x10,      // d a b
    OP_SUB = 0x11,      // d a b
    OP_EMUL = 0x12,     // d a b
    OP_EDIV = 0x13,     // d a b
    OP_MUL = 0x14,      // d a b
    OP_SCALE = 0x15,    // d a k
    OP_OFFSET = 0x16,   // d a k
    OP_APPLY = 0x17,    // d a fn
    OP_SOFTMAX = 0x18,  // d a
    OP_SUM = 0x19,      // d a how (0 each column, 1 each row)
    OP_ARGMAX = 0x1a,   // d a
    OP_PICK = 0x1b,     // d a b row
    OP_ROTATE = 0x20,   // r axis angle
    OP_PROJECT = 0x21,  // d a dist
    OP_TURN = 0x22,     // d axis a i
    OP_SCREEN = 0x30,   // x(2) y(2) w(2) h(2)
    OP_CLEAR = 0x31,
    OP_LINES = 0x32,    // p e m
    OP_SEND = 0x33,
};

// The functions of APPLY
enum {
    FN_NEG, FN_ABS, FN_RELU, FN_SIGMOID, FN_TANH, FN_SQRT, FN_EXP, FN_LOG,
    FN_SIN, FN_COS, FN_ROUND, FN_FLOOR, FN_SQUARE, FN_STEP, FN_COUNT
};

// The element formats: bits 0-3 fraction bits, bits 4-5 the type
enum { T_S16, T_S8, T_U8 };

const char *op_name(int op)
{
    switch (op) {
        case OP_END: return "END";
        case OP_LOAD: return "LOAD";
        case OP_STORE: return "STORE";
        case OP_FILL: return "FILL";
        case OP_IDENT: return "IDENT";
        case OP_RANGE: return "RANGE";
        case OP_COPY: return "COPY";
        case OP_TRANSP: return "TRANSP";
        case OP_JOIN: return "JOIN";
        case OP_FREE: return "FREE";
        case OP_RESET: return "RESET";
        case OP_DEFINE: return "DEFINE";
        case OP_RUN: return "RUN";
        case OP_CLOCK: return "CLOCK";
        case OP_TURN: return "TURN";
        case OP_ADD: return "ADD";
        case OP_SUB: return "SUB";
        case OP_EMUL: return "EMUL";
        case OP_EDIV: return "EDIV";
        case OP_MUL: return "MUL";
        case OP_SCALE: return "SCALE";
        case OP_OFFSET: return "OFFSET";
        case OP_APPLY: return "APPLY";
        case OP_SOFTMAX: return "SOFTMAX";
        case OP_SUM: return "SUM";
        case OP_ARGMAX: return "ARGMAX";
        case OP_PICK: return "PICK";
        case OP_SCREEN: return "SCREEN";
        case OP_CLEAR: return "CLEAR";
        case OP_LINES: return "LINES";
        case OP_SEND: return "SEND";
        case OP_ROTATE: return "ROTATE";
        case OP_PROJECT: return "PROJECT";
        default: return "?";
    }
}

int bytes_per_element(int fmt)
{
    return (fmt >> 4) == T_S16 ? 2 : 1;
}

float from_fixed(const uint8_t *p, int fmt)
{
    float scale = 1.0f / (float)(1 << (fmt & 15));
    switch (fmt >> 4) {
        case T_S16: return (float)(int16_t)(p[0] | (p[1] << 8)) * scale;
        case T_S8: return (float)(int8_t)p[0] * scale;
        default: return (float)p[0] * scale;
    }
}

// Rounded to the nearest, and held within the type's range
void to_fixed(float x, int fmt, std::vector<uint8_t> &out)
{
    float lo = -32768, hi = 32767;
    if ((fmt >> 4) == T_S8) {
        lo = -128;
        hi = 127;
    } else if ((fmt >> 4) == T_U8) {
        lo = 0;
        hi = 255;
    }
    float v = std::floor(x * (float)(1 << (fmt & 15)) + 0.5f);
    if (std::isnan(v)) {
        v = 0;
    }
    v = v < lo ? lo : v > hi ? hi : v;
    int i = (int)v;
    out.push_back(i & 0xff);
    if ((fmt >> 4) == T_S16) {
        out.push_back((i >> 8) & 0xff);
    }
}

float apply(int fn, float x)
{
    switch (fn) {
        case FN_NEG: return -x;
        case FN_ABS: return std::fabs(x);
        case FN_RELU: return x > 0 ? x : 0;
        case FN_SIGMOID: return 1.0f / (1.0f + std::exp(-x));
        case FN_TANH: return std::tanh(x);
        case FN_SQRT: return x > 0 ? std::sqrt(x) : 0;
        case FN_EXP: return std::exp(x);
        case FN_LOG: return std::log(x);
        case FN_SIN: return std::sin(x);
        case FN_COS: return std::cos(x);
        case FN_ROUND: return std::floor(x + 0.5f);
        case FN_FLOOR: return std::floor(x);
        case FN_SQUARE: return x * x;
        default: return x > 0 ? 1 : 0;      // FN_STEP
    }
}

}  // namespace

Npu::Npu(size_t max_elements) : max_elements_(max_elements)
{
    clock_ms_ = [] {
        return (uint32_t)std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now().time_since_epoch()).count();
    };
}

void Npu::reset()
{
    for (Matrix &m : reg_) {
        m = Matrix();
    }
    for (std::vector<uint8_t> &s : script_) {
        s.clear();
    }
    clocked_ = false;
    ax2_ = ay2_ = -1;
}

// ---------------------------------------------------------------------
// The C64's screen: 320 x 200, a bit per pixel (set = black), in the
// C64's bitmap layout: byte (y / 8) * 320 + (x / 8) * 8 + y % 8
// ---------------------------------------------------------------------
static const int SCREEN_BYTES = 8000;

static inline int screen_byte(int x, int y)
{
    return (y >> 3) * 320 + (x >> 3) * 8 + (y & 7);
}

void Npu::plot(int x, int y)
{
    if (x >= ax1_ && x <= ax2_ && y >= ay1_ && y <= ay2_) {
        shadow_[screen_byte(x, y)] |= 0x80 >> (x & 7);
    }
}

// a line from (x1, y1) to (x2, y2), on the screen, clipped to the area
void Npu::line(int x1, int y1, int x2, int y2)
{
    int dx = std::abs(x2 - x1), dy = std::abs(y2 - y1);
    int sx = x1 < x2 ? 1 : -1, sy = y1 < y2 ? 1 : -1;
    int err = dx - dy;
    for (;;) {
        plot(x1, y1);
        if (x1 == x2 && y1 == y2) {
            break;
        }
        int e2 = 2 * err;
        if (e2 > -dy) {
            err -= dy;
            x1 += sx;
        }
        if (e2 < dx) {
            err += dx;
            y1 += sy;
        }
    }
}

// The bytes of the area the C64 doesn't have yet, as runs: offset in the
// bitmap (2: bit 15 set if the bytes are 8 apart, along a pixel row),
// count (1), the bytes.  Runs along a pixel row first (4 bytes or more),
// then runs in the bitmap's order, taking in gaps of up to 3 bytes.
bool Npu::send(std::vector<uint8_t> &out, size_t out_max)
{
    std::vector<uint8_t> sent = sent_;
    size_t start = out.size();
    auto run = [&](int at, int count, int step) {
        if (out.size() + 3 + count > out_max) {
            return false;
        }
        out.push_back(at & 0xff);
        out.push_back(((at >> 8) & 0x1f) | (step == 8 ? 0x80 : 0));
        out.push_back(count);
        for (int i = 0; i < count; i++) {
            out.push_back(shadow_[at + i * step]);
            sent[at + i * step] = shadow_[at + i * step];
        }
        return true;
    };
    int c1 = ax1_ >> 3, c2 = ax2_ >> 3;
    for (int y = ay1_; y <= ay2_; y++) {            // along the rows
        int c = c1;
        while (c <= c2) {
            int n = 0;
            while (c + n <= c2 && n < 32 && shadow_[screen_byte((c + n) * 8, y)] != sent[screen_byte((c + n) * 8, y)]) {
                n++;
            }
            if (n >= 4) {
                if (!run(screen_byte(c * 8, y), n, 8)) {
                    out.resize(start);
                    return false;
                }
                c += n;
            } else {
                c += n ? n : 1;
            }
        }
    }
    for (int r = ay1_ >> 3; r <= ay2_ >> 3; r++) {  // in the bitmap's order
        int first = r * 320 + c1 * 8, last = r * 320 + c2 * 8 + 7;
        auto inside = [&](int a) {
            int y = r * 8 + (a & 7);
            return a <= last && y >= ay1_ && y <= ay2_;
        };
        for (int a = first; a <= last; a++) {
            if (!inside(a) || shadow_[a] == sent[a]) {
                continue;
            }
            int end = a;                            // the last changed byte
            for (int b = a + 1; b <= last && b - a < 255 && inside(b) && b - end <= 4; b++) {
                if (shadow_[b] != sent[b]) {
                    end = b;
                }
            }
            if (!run(a, end - a + 1, 1)) {
                out.resize(start);
                return false;
            }
            a = end;
        }
    }
    sent_.swap(sent);
    return true;
}

// A rotation matrix: about x (0), y (1) or z (2), 3x3, or in the plane
// (3), 2x2, by t radians, for column vectors
void Npu::rotation(int axis, float t, Matrix &m)
{
    float c = std::cos(t), s = std::sin(t);
    if (axis == 3) {
        m.rows = m.cols = 2;
        m.v = {c, -s, s, c};
    } else {
        m.rows = m.cols = 3;
        if (axis == 0) {
            m.v = {1, 0, 0, 0, c, -s, 0, s, c};
        } else if (axis == 1) {
            m.v = {c, 0, s, 0, 1, 0, -s, 0, c};
        } else {
            m.v = {c, -s, 0, s, c, 0, 0, 0, 1};
        }
    }
}

uint8_t Npu::fail(uint8_t status, const std::string &why)
{
    char where[48];
    if (in_ >= 0) {
        snprintf(where, sizeof where, "Script %d, instruction %d (%s): ", in_, step_, op_name_);
    } else {
        snprintf(where, sizeof where, "Instruction %d (%s): ", step_, op_name_);
    }
    message_ = where + why;
    return status;
}

std::string Npu::dims(const Matrix &m) const
{
    return std::to_string(m.rows) + "x" + std::to_string(m.cols);
}

// The program's next bytes
bool Npu::need(size_t bytes)
{
    return pos_ + bytes <= n_;
}

bool Npu::byte(int &b)
{
    if (!need(1)) {
        return false;
    }
    b = p_[pos_++];
    return true;
}

bool Npu::reg(int &r)
{
    return byte(r) && r < REGISTERS;
}

bool Npu::size(int &rows, int &cols)
{
    return byte(rows) && byte(cols) && rows > 0 && cols > 0;
}

bool Npu::fixed32(float &f)
{
    if (!need(4)) {
        return false;
    }
    const uint8_t *q = p_ + pos_;
    int32_t v = (int32_t)(q[0] | (q[1] << 8) | (q[2] << 16) | ((uint32_t)q[3] << 24));
    pos_ += 4;
    f = (float)v / 65536.0f;
    return true;
}

bool Npu::fmt(int &f)
{
    return byte(f) && (f >> 4) <= T_U8;
}

// Register r = m, if there is room
bool Npu::set(int r, Matrix &&m)
{
    size_t used = 0;
    for (int i = 0; i < REGISTERS; i++) {
        if (i != r) {
            used += reg_[i].v.size();
        }
    }
    if (used + m.v.size() > max_elements_) {
        return false;
    }
    reg_[r] = std::move(m);
    return true;
}

// a (op) b, element by element.  b may be the same size as a, or one
// row, one column or one element, used for every row, column or element.
bool Npu::broadcast(const Matrix &a, const Matrix &b, Matrix &out, int how)
{
    bool rows_ok = b.rows == a.rows || b.rows == 1;
    bool cols_ok = b.cols == a.cols || b.cols == 1;
    if (!rows_ok || !cols_ok) {
        return false;
    }
    out.rows = a.rows;
    out.cols = a.cols;
    out.v.resize(a.v.size());
    for (int r = 0; r < a.rows; r++) {
        for (int c = 0; c < a.cols; c++) {
            float x = a.at(r, c);
            float y = b.at(b.rows == 1 ? 0 : r, b.cols == 1 ? 0 : c);
            float z;
            switch (how) {
                case OP_ADD: z = x + y; break;
                case OP_SUB: z = x - y; break;
                case OP_EMUL: z = x * y; break;
                default: z = x / y; break;
            }
            out.at(r, c) = z;
        }
    }
    return true;
}

uint8_t Npu::run(const uint8_t *p, size_t n, std::vector<uint8_t> &out, size_t out_max)
{
    message_ = "Success";
    in_ = -1;
    return exec(p, n, out, out_max, 0);
}

uint8_t Npu::exec(const uint8_t *p, size_t n, std::vector<uint8_t> &out, size_t out_max, int depth)
{
    p_ = p;
    n_ = n;
    pos_ = 0;
    step_ = 0;
    const std::string empty = "a register is empty";
    const std::string memory = "out of matrix memory";

    while (pos_ < n_) {
        int op = p_[pos_++];
        step_++;
        op_name_ = op_name(op);
        int d, a, b, rows, cols, how;
        float k, k2;
        Matrix m;

        switch (op) {
        case OP_END:
            return 0;

        case OP_LOAD: {
            int f;
            if (!reg(d) || !size(rows, cols) || !fmt(f)) {
                return fail(BAD_PROGRAM, "bad operands");
            }
            size_t count = (size_t)rows * cols;
            if (!need(count * bytes_per_element(f))) {
                return fail(BAD_PROGRAM, "the data is cut short");
            }
            m.rows = rows;
            m.cols = cols;
            m.v.resize(count);
            for (size_t i = 0; i < count; i++) {
                m.v[i] = from_fixed(p_ + pos_, f);
                pos_ += bytes_per_element(f);
            }
            if (!set(d, std::move(m))) {
                return fail(MEMORY, memory);
            }
            break;
        }

        case OP_STORE: {
            int f;
            if (!reg(a) || !fmt(f)) {
                return fail(BAD_PROGRAM, "bad operands");
            }
            const Matrix &s = reg_[a];
            if (s.rows == 0) {
                return fail(EMPTY, empty);
            }
            if (out.size() + 2 + s.v.size() * bytes_per_element(f) > out_max) {
                return fail(TOO_MUCH, "the results are too big for one response");
            }
            out.push_back(s.rows);
            out.push_back(s.cols);
            for (float x : s.v) {
                to_fixed(x, f, out);
            }
            break;
        }

        case OP_FILL:
        case OP_RANGE:
            if (!reg(d) || !size(rows, cols) || !fixed32(k)) {
                return fail(BAD_PROGRAM, "bad operands");
            }
            k2 = 0;
            if (op == OP_RANGE && !fixed32(k2)) {
                return fail(BAD_PROGRAM, "bad operands");
            }
            m.rows = rows;
            m.cols = cols;
            m.v.resize((size_t)rows * cols);
            for (size_t i = 0; i < m.v.size(); i++) {
                m.v[i] = k + k2 * (float)i;
            }
            if (!set(d, std::move(m))) {
                return fail(MEMORY, memory);
            }
            break;

        case OP_IDENT:
            if (!reg(d) || !byte(rows) || rows == 0) {
                return fail(BAD_PROGRAM, "bad operands");
            }
            m.rows = m.cols = rows;
            m.v.assign((size_t)rows * rows, 0.0f);
            for (int i = 0; i < rows; i++) {
                m.at(i, i) = 1;
            }
            if (!set(d, std::move(m))) {
                return fail(MEMORY, memory);
            }
            break;

        case OP_COPY:
        case OP_TRANSP:
            if (!reg(d) || !reg(a)) {
                return fail(BAD_PROGRAM, "bad operands");
            }
            if (reg_[a].rows == 0) {
                return fail(EMPTY, empty);
            }
            if (op == OP_COPY) {
                m = reg_[a];
            } else {
                const Matrix &s = reg_[a];
                m.rows = s.cols;
                m.cols = s.rows;
                m.v.resize(s.v.size());
                for (int r = 0; r < s.rows; r++) {
                    for (int c = 0; c < s.cols; c++) {
                        m.at(c, r) = s.at(r, c);
                    }
                }
            }
            if (!set(d, std::move(m))) {
                return fail(MEMORY, memory);
            }
            break;

        case OP_JOIN: {
            if (!reg(d) || !reg(a) || !reg(b) || !byte(how) || how > 1) {
                return fail(BAD_PROGRAM, "bad operands");
            }
            const Matrix &x = reg_[a], &y = reg_[b];
            if (x.rows == 0 || y.rows == 0) {
                return fail(EMPTY, empty);
            }
            if (how == 0) {             // side by side
                if (x.rows != y.rows || x.cols + y.cols > 255) {
                    return fail(SIZES, "can't put " + dims(x) + " beside " + dims(y));
                }
                m.rows = x.rows;
                m.cols = x.cols + y.cols;
                m.v.resize((size_t)m.rows * m.cols);
                for (int r = 0; r < m.rows; r++) {
                    for (int c = 0; c < m.cols; c++) {
                        m.at(r, c) = c < x.cols ? x.at(r, c) : y.at(r, c - x.cols);
                    }
                }
            } else {                    // a above b
                if (x.cols != y.cols || x.rows + y.rows > 255) {
                    return fail(SIZES, "can't put " + dims(x) + " above " + dims(y));
                }
                m.rows = x.rows + y.rows;
                m.cols = x.cols;
                m.v = x.v;
                m.v.insert(m.v.end(), y.v.begin(), y.v.end());
            }
            if (!set(d, std::move(m))) {
                return fail(MEMORY, memory);
            }
            break;
        }

        case OP_FREE:
            if (!reg(d)) {
                return fail(BAD_PROGRAM, "bad operands");
            }
            reg_[d] = Matrix();
            break;

        case OP_RESET:
            reset();
            break;

        case OP_DEFINE: {
            int s, lo, hi;
            if (!byte(s) || s >= SCRIPTS || !byte(lo) || !byte(hi)) {
                return fail(BAD_PROGRAM, "bad operands");
            }
            size_t length = lo | (hi << 8);
            if (!need(length)) {
                return fail(BAD_PROGRAM, "the script is cut short");
            }
            size_t used = 0;
            for (int i = 0; i < SCRIPTS; i++) {
                used += i == s ? 0 : script_[i].size();
            }
            if (used + length > SCRIPT_BYTES) {
                return fail(MEMORY, "out of script memory");
            }
            script_[s].assign(p_ + pos_, p_ + pos_ + length);
            pos_ += length;
            break;
        }

        case OP_RUN: {
            int s;
            if (!byte(s) || s >= SCRIPTS) {
                return fail(BAD_PROGRAM, "bad operands");
            }
            if (script_[s].empty()) {
                return fail(EMPTY, "script " + std::to_string(s) + " is empty");
            }
            if (depth >= DEPTH) {
                return fail(BAD_PROGRAM, "scripts run each other too deeply");
            }
            std::vector<uint8_t> code = script_[s];     // (it may redefine itself)
            const uint8_t *was_p = p_;
            size_t was_n = n_, was_pos = pos_;
            int was_step = step_, was_in = in_;
            const char *was_name = op_name_;
            in_ = s;
            uint8_t status = exec(code.data(), code.size(), out, out_max, depth + 1);
            if (status) {
                return status;          // (the message says where)
            }
            p_ = was_p;
            n_ = was_n;
            pos_ = was_pos;
            step_ = was_step;
            in_ = was_in;
            op_name_ = was_name;
            break;
        }

        case OP_CLOCK: {
            if (!reg(d)) {
                return fail(BAD_PROGRAM, "bad operands");
            }
            uint32_t now = clock_ms_();
            float dt = clocked_ ? (float)(uint32_t)(now - last_clock_) / 1000.0f : 0.0f;
            clocked_ = true;
            last_clock_ = now;
            m.rows = m.cols = 1;
            m.v = {dt < 0.25f ? dt : 0.25f};
            if (!set(d, std::move(m))) {
                return fail(MEMORY, memory);
            }
            break;
        }

        case OP_ADD:
        case OP_SUB:
        case OP_EMUL:
        case OP_EDIV:
        case OP_MUL: {
            if (!reg(d) || !reg(a) || !reg(b)) {
                return fail(BAD_PROGRAM, "bad operands");
            }
            const Matrix &x = reg_[a], &y = reg_[b];
            if (x.rows == 0 || y.rows == 0) {
                return fail(EMPTY, empty);
            }
            if (op == OP_MUL) {
                if (x.cols != y.rows) {
                    return fail(SIZES, "can't multiply " + dims(x) + " by " + dims(y));
                }
                m.rows = x.rows;
                m.cols = y.cols;
                m.v.assign((size_t)m.rows * m.cols, 0.0f);
                for (int r = 0; r < m.rows; r++) {
                    for (int c = 0; c < m.cols; c++) {
                        float sum = 0;
                        for (int i = 0; i < x.cols; i++) {
                            sum += x.at(r, i) * y.at(i, c);
                        }
                        m.at(r, c) = sum;
                    }
                }
            } else if (!broadcast(x, y, m, op)) {
                return fail(SIZES, "can't combine " + dims(x) + " with " + dims(y));
            }
            if (!set(d, std::move(m))) {
                return fail(MEMORY, memory);
            }
            break;
        }

        case OP_SCALE:
        case OP_OFFSET:
        case OP_APPLY:
        case OP_SOFTMAX:
        case OP_SUM:
        case OP_ARGMAX:
        case OP_PROJECT: {
            if (!reg(d) || !reg(a)) {
                return fail(BAD_PROGRAM, "bad operands");
            }
            k = 0;
            how = 0;
            if (op == OP_SCALE || op == OP_OFFSET || op == OP_PROJECT) {
                if (!fixed32(k)) {
                    return fail(BAD_PROGRAM, "bad operands");
                }
            } else if (op == OP_APPLY || op == OP_SUM) {
                if (!byte(how) || how >= (op == OP_APPLY ? FN_COUNT : 2)) {
                    return fail(BAD_PROGRAM, "bad operands");
                }
            }
            const Matrix &x = reg_[a];
            if (x.rows == 0) {
                return fail(EMPTY, empty);
            }
            if (op == OP_SCALE || op == OP_OFFSET || op == OP_APPLY) {
                m = x;
                for (float &e : m.v) {
                    e = op == OP_SCALE ? e * k : op == OP_OFFSET ? e + k : apply(how, e);
                }
            } else if (op == OP_SOFTMAX) {
                m = x;
                for (int c = 0; c < x.cols; c++) {
                    float top = x.at(0, c), sum = 0;
                    for (int r = 1; r < x.rows; r++) {
                        top = std::fmax(top, x.at(r, c));
                    }
                    for (int r = 0; r < x.rows; r++) {
                        sum += m.at(r, c) = std::exp(x.at(r, c) - top);
                    }
                    for (int r = 0; r < x.rows; r++) {
                        m.at(r, c) /= sum;
                    }
                }
            } else if (op == OP_SUM) {
                m.rows = how ? x.rows : 1;
                m.cols = how ? 1 : x.cols;
                m.v.assign((size_t)m.rows * m.cols, 0.0f);
                for (int r = 0; r < x.rows; r++) {
                    for (int c = 0; c < x.cols; c++) {
                        m.at(how ? r : 0, how ? 0 : c) += x.at(r, c);
                    }
                }
            } else if (op == OP_ARGMAX) {
                m.rows = 1;
                m.cols = x.cols;
                m.v.resize(x.cols);
                for (int c = 0; c < x.cols; c++) {
                    int best = 0;
                    for (int r = 1; r < x.rows; r++) {
                        if (x.at(r, c) > x.at(best, c)) {
                            best = r;
                        }
                    }
                    m.v[c] = (float)best;
                }
            } else {                    // PROJECT: 3xn -> 2xn, seen from dist in front
                if (x.rows != 3) {
                    return fail(SIZES, "needs 3 rows (x, y, z), not " + dims(x));
                }
                m.rows = 2;
                m.cols = x.cols;
                m.v.resize((size_t)2 * x.cols);
                for (int c = 0; c < x.cols; c++) {
                    float f = k / (k + x.at(2, c));
                    m.at(0, c) = x.at(0, c) * f;
                    m.at(1, c) = x.at(1, c) * f;
                }
            }
            if (!set(d, std::move(m))) {
                return fail(MEMORY, memory);
            }
            break;
        }

        case OP_PICK: {
            if (!reg(d) || !reg(a) || !reg(b) || !byte(rows)) {
                return fail(BAD_PROGRAM, "bad operands");
            }
            const Matrix &x = reg_[a], &y = reg_[b];
            if (x.rows == 0 || y.rows == 0) {
                return fail(EMPTY, empty);
            }
            if (rows >= y.rows) {
                return fail(SIZES, "no row " + std::to_string(rows) + " in " + dims(y));
            }
            m.rows = 1;
            m.cols = y.cols;
            m.v.resize(y.cols);
            for (int c = 0; c < y.cols; c++) {
                float f = y.at(rows, c);
                if (!(f >= 0) || f >= (float)x.v.size()) {
                    return fail(SIZES, "no element " + std::to_string((int)f) + " in " + dims(x));
                }
                m.v[c] = x.v[(size_t)f];
            }
            if (!set(d, std::move(m))) {
                return fail(MEMORY, memory);
            }
            break;
        }

        case OP_SCREEN: {
            if (!need(8)) {
                return fail(BAD_PROGRAM, "bad operands");
            }
            const uint8_t *q = p_ + pos_;
            int x = (int16_t)(q[0] | (q[1] << 8)), y = (int16_t)(q[2] | (q[3] << 8));
            int w = q[4] | (q[5] << 8), h = q[6] | (q[7] << 8);
            pos_ += 8;
            if (shadow_.empty()) {
                shadow_.assign(SCREEN_BYTES, 0);
                sent_.assign(SCREEN_BYTES, 0);
            }
            ox_ = x;
            oy_ = y;
            ax1_ = std::max(0, (x + 7) & ~7);       // whole bytes, on the screen
            ax2_ = std::min(319, ((x + w) & ~7) - 1);
            ay1_ = std::max(0, y);
            ay2_ = std::min(199, y + h - 1);
            for (int yy = ay1_; yy <= ay2_; yy++) { // the C64's area is white
                for (int xx = ax1_; xx <= ax2_; xx += 8) {
                    shadow_[screen_byte(xx, yy)] = sent_[screen_byte(xx, yy)] = 0;
                }
            }
            break;
        }

        case OP_CLEAR:
            if (!has_area()) {
                return fail(EMPTY, "no SCREEN yet");
            }
            for (int yy = ay1_; yy <= ay2_; yy++) {
                for (int xx = ax1_; xx <= ax2_; xx += 8) {
                    shadow_[screen_byte(xx, yy)] = 0;
                }
            }
            break;

        case OP_LINES: {
            if (!reg(a) || !reg(b) || !byte(how) || (how != 255 && how >= REGISTERS)) {
                return fail(BAD_PROGRAM, "bad operands");
            }
            if (!has_area()) {
                return fail(EMPTY, "no SCREEN yet");
            }
            const Matrix &pts = reg_[a], &ends = reg_[b];
            if (pts.rows == 0 || ends.rows == 0 || (how != 255 && reg_[how].rows == 0)) {
                return fail(EMPTY, empty);
            }
            if (pts.rows != 2 || ends.rows < 2) {
                return fail(SIZES, "needs 2 x n points and 2 x e ends, not " + dims(pts) + " and " + dims(ends));
            }
            if (how != 255 && (int)reg_[how].v.size() != ends.cols) {
                return fail(SIZES, "needs a mask of " + std::to_string(ends.cols) + ", not " + dims(reg_[how]));
            }
            for (int e = 0; e < ends.cols; e++) {
                if (how != 255 && !(reg_[how].v[e] > 0)) {
                    continue;
                }
                float i = ends.at(0, e), j = ends.at(1, e);
                if (!(i >= 0 && i < pts.cols && j >= 0 && j < pts.cols)) {
                    return fail(SIZES, "no point " + std::to_string((int)(i < pts.cols ? j : i)) +
                                       " in " + dims(pts));
                }
                float x1 = pts.at(0, (int)i), y1 = pts.at(1, (int)i);
                float x2 = pts.at(0, (int)j), y2 = pts.at(1, (int)j);
                if (!(std::fabs(x1) < 2000 && std::fabs(y1) < 2000 && std::fabs(x2) < 2000 && std::fabs(y2) < 2000)) {
                    continue;                       // (far off the screen, or not a number)
                }
                line(ox_ + (int)std::floor(x1 + 0.5f), oy_ + (int)std::floor(y1 + 0.5f),
                     ox_ + (int)std::floor(x2 + 0.5f), oy_ + (int)std::floor(y2 + 0.5f));
            }
            break;
        }

        case OP_SEND:
            if (!has_area()) {
                return fail(EMPTY, "no SCREEN yet");
            }
            if (!send(out, out_max)) {
                return fail(TOO_MUCH, "the screen's changes are too big for one response");
            }
            break;

        case OP_ROTATE: {
            int axis;
            if (!reg(d) || !byte(axis) || axis > 3 || !need(2)) {
                return fail(BAD_PROGRAM, "bad operands");
            }
            int angle = p_[pos_] | (p_[pos_ + 1] << 8);
            pos_ += 2;
            rotation(axis, (float)angle * 6.28318530718f / 65536.0f, m);
            if (!set(d, std::move(m))) {
                return fail(MEMORY, memory);
            }
            break;
        }

        case OP_TURN: {
            int axis, i;
            if (!reg(d) || !byte(axis) || axis > 3 || !reg(a) || !byte(i)) {
                return fail(BAD_PROGRAM, "bad operands");
            }
            const Matrix &x = reg_[a];
            if (x.rows == 0) {
                return fail(EMPTY, empty);
            }
            if ((size_t)i >= x.v.size()) {
                return fail(SIZES, "no element " + std::to_string(i) + " in " + dims(x));
            }
            rotation(axis, x.v[i], m);
            if (!set(d, std::move(m))) {
                return fail(MEMORY, memory);
            }
            break;
        }

        default:
            return fail(BAD_PROGRAM, "unknown instruction");
        }
    }
    return 0;
}
