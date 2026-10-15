// npu.h - the WiC64's matrix unit: the C64 sends matrices, the ESP32
// works on them and sends the results back (docs/npu.md)
//
// One request (WiC64 command $90) carries a program: instructions on 32
// matrix registers, which keep their contents between requests.  The
// results of its STORE instructions are the response.  Elements are
// held as floats; the C64 sends and receives them as fixed-point
// numbers, 8 or 16 bits with 0 to 15 fraction bits.  A program can also
// keep scripts on the WiC64 (DEFINE) to be run later (RUN): an animation
// is sent once, and each frame is then one short request.  And it can
// draw: the WiC64 keeps a copy of the C64's screen, draws lines on it
// (SCREEN, CLEAR, LINES), and sends the bytes that changed (SEND), in the
// C64's bitmap layout, for the C64 to write straight into its bitmap.
//
// Plain C++, shared by the firmware (firmware/) and Frodo's emulated
// WiC64 (frodo4/src/WiC64.cpp).  GPL-2.0, like the rest of the project.

#pragma once
#include <cstddef>
#include <cstdint>
#include <functional>
#include <string>
#include <vector>

class Npu {
public:
    static const int REGISTERS = 32;
    static const int SCRIPTS = 8;
    static const size_t SCRIPT_BYTES = 4096;    // all the scripts together
    static const int DEPTH = 4;                 // scripts running scripts

    // At most max_elements elements in all the registers together
    explicit Npu(size_t max_elements);

    // The clock for CLOCK, in milliseconds (it may wrap).  The default
    // is the host's own.
    void set_clock(std::function<uint32_t()> ms) { clock_ms_ = ms; }

    // Run the program of n bytes at p.  The results of STORE are
    // appended to out (at most out_max bytes).  Returns 0, or an error
    // status (below), with message() saying what went wrong.
    uint8_t run(const uint8_t *p, size_t n, std::vector<uint8_t> &out, size_t out_max);

    const std::string &message() const { return message_; }

    // Empty all the registers and scripts
    void reset();

    // Status codes (0 = success)
    enum {
        BAD_PROGRAM = 20,       // an unknown instruction, or one cut short
        EMPTY = 32,             // a register (or script) used before it was set
        SIZES = 33,             // the sizes of the matrices don't fit
        MEMORY = 34,            // more than the matrix memory
        TOO_MUCH = 35,          // the results are too big for one response
    };

private:
    struct Matrix {
        int rows = 0, cols = 0;
        std::vector<float> v;   // row by row
        float &at(int r, int c) { return v[(size_t)r * cols + c]; }
        float at(int r, int c) const { return v[(size_t)r * cols + c]; }
    };

    Matrix reg_[REGISTERS];
    std::vector<uint8_t> script_[SCRIPTS];
    size_t max_elements_;
    std::string message_;
    std::function<uint32_t()> clock_ms_;
    bool clocked_ = false;
    uint32_t last_clock_ = 0;

    // The program being run: the request, or script `in_`
    const uint8_t *p_ = nullptr;
    size_t n_ = 0, pos_ = 0;
    int step_ = 0;
    int in_ = -1;
    const char *op_name_ = "";

    uint8_t exec(const uint8_t *p, size_t n, std::vector<uint8_t> &out, size_t out_max, int depth);
    static void rotation(int axis, float t, Matrix &m);

    // The C64's screen (SCREEN, CLEAR, LINES, SEND): what it should show
    // and what it has been sent, 8000 bytes each in its bitmap's layout;
    // the area to draw in (whole bytes, on the screen, inclusive) and
    // where (0, 0) of the drawing is on the screen
    std::vector<uint8_t> shadow_, sent_;
    int ax1_ = 0, ax2_ = -1, ay1_ = 0, ay2_ = -1;
    int ox_ = 0, oy_ = 0;
    bool has_area() const { return ax2_ >= ax1_ && ay2_ >= ay1_ && !shadow_.empty(); }
    void plot(int x, int y);
    void line(int x1, int y1, int x2, int y2);
    bool send(std::vector<uint8_t> &out, size_t out_max);

    bool need(size_t bytes);
    bool byte(int &b);
    bool reg(int &r);
    bool size(int &rows, int &cols);
    bool fixed32(float &f);
    bool fmt(int &f);

    bool set(int r, Matrix &&m);
    uint8_t fail(uint8_t status, const std::string &why);
    std::string dims(const Matrix &m) const;

    bool broadcast(const Matrix &a, const Matrix &b, Matrix &out, int how);
};
