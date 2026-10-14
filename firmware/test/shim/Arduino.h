// Arduino.h - just enough of the Arduino core (ESP32) to build the
// firmware's file service and user port driver on the host, for the
// test bench (test/c64sim.cpp)

#pragma once
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <mutex>
#include <string>
#include <type_traits>

using std::max;
using std::min;

class String {
public:
    String() {}
    String(const char *s) : s_(s ? s : "") {}
    String(const std::string &s) : s_(s) {}
    String(char c) : s_(1, c) {}
    template <typename T, typename = typename std::enable_if<std::is_integral<T>::value>::type>
    explicit String(T n) : s_(std::to_string(n)) {}

    size_t length() const { return s_.size(); }
    const char *c_str() const { return s_.c_str(); }
    void reserve(size_t n) { s_.reserve(n); }
    char operator[](size_t i) const { return i < s_.size() ? s_[i] : 0; }
    char &operator[](size_t i) { return s_[i]; }

    String &operator+=(const String &o) { s_ += o.s_; return *this; }
    String &operator+=(const char *o) { s_ += o; return *this; }
    String &operator+=(char c) { s_ += c; return *this; }
    friend String operator+(const String &a, const String &b) { return String(a.s_ + b.s_); }
    friend String operator+(const String &a, const char *b) { return String(a.s_ + b); }
    friend String operator+(const char *a, const String &b) { return String(a + b.s_); }
    friend String operator+(const String &a, char b) { return String(a.s_ + b); }
    bool operator==(const String &o) const { return s_ == o.s_; }
    bool operator==(const char *o) const { return s_ == o; }
    bool operator!=(const String &o) const { return s_ != o.s_; }

    String substring(size_t from) const { return from < s_.size() ? String(s_.substr(from)) : String(); }
    String substring(size_t from, size_t to) const
    {
        if (to > s_.size()) to = s_.size();
        return from < to ? String(s_.substr(from, to - from)) : String();
    }
    int indexOf(char c, size_t from = 0) const { auto p = s_.find(c, from); return p == std::string::npos ? -1 : (int)p; }
    int indexOf(const char *t, size_t from = 0) const { auto p = s_.find(t, from); return p == std::string::npos ? -1 : (int)p; }
    int lastIndexOf(char c) const { auto p = s_.rfind(c); return p == std::string::npos ? -1 : (int)p; }
    bool startsWith(const String &t) const { return s_.compare(0, t.s_.size(), t.s_) == 0; }
    bool endsWith(const String &t) const
    {
        return s_.size() >= t.s_.size() && s_.compare(s_.size() - t.s_.size(), t.s_.size(), t.s_) == 0;
    }
    void trim()
    {
        size_t a = s_.find_first_not_of(" \t\r\n");
        size_t b = s_.find_last_not_of(" \t\r\n");
        s_ = a == std::string::npos ? "" : s_.substr(a, b - a + 1);
    }

private:
    std::string s_;
};

uint32_t millis();
void delay(uint32_t ms);
int64_t esp_timer_get_time();

// GPIO (see soc/gpio_struct.h)
enum { LOW = 0, HIGH = 1, INPUT = 1, OUTPUT = 3, INPUT_PULLUP = 5, FALLING = 2 };
void pinMode(int pin, int mode);
void digitalWrite(int pin, int level);
inline int digitalPinToInterrupt(int pin) { return pin; }
void attachInterrupt(int pin, void (*isr)(), int mode);

#define IRAM_ATTR
typedef std::recursive_mutex portMUX_TYPE;
#define portMUX_INITIALIZER_UNLOCKED {}
#define portENTER_CRITICAL(m) (m)->lock()
#define portEXIT_CRITICAL(m) (m)->unlock()
#define portENTER_CRITICAL_ISR(m) (m)->lock()
#define portEXIT_CRITICAL_ISR(m) (m)->unlock()
