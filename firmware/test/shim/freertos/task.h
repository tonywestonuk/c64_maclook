// freertos/task.h - the test bench has no scheduler to pause
#pragma once
inline void vTaskSuspendAll() {}
inline int xTaskResumeAll() { return 0; }
