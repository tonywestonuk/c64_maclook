// soc/gpio_struct.h - the ESP32's GPIO registers, for the test bench:
// writes go to the simulated user port (test/c64sim.cpp)

#pragma once
#include <cstdint>

struct GpioReg {
    void (*on_write)(uint32_t) = nullptr;
    GpioReg &operator=(uint32_t v)
    {
        if (on_write) on_write(v);
        return *this;
    }
};

struct GpioDev {
    volatile uint32_t in;       // the levels on GPIO 0-31
    GpioReg out_w1ts, out_w1tc, enable_w1ts, enable_w1tc;
    volatile uint32_t status;   // edges latched (interrupt status)
    GpioReg status_w1tc;
};

extern GpioDev GPIO;
