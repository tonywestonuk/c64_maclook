// driver/gpio.h - the test bench's stand-in (see c64sim.cpp)
#pragma once
typedef int gpio_num_t;
void gpio_intr_disable(gpio_num_t pin);
void gpio_intr_enable(gpio_num_t pin);
