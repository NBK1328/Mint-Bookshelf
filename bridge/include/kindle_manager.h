#ifndef KINDLE_MANAGER_H
#define KINDLE_MANAGER_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

const char* KM_GetVersion(void);
void KM_FreeMemory(void* ptr);

#ifdef __cplusplus
}
#endif

#endif
