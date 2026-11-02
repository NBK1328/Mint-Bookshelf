#ifndef KINDLE_MANAGER_H
#define KINDLE_MANAGER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

const char *KM_Initialize(const char *dbPath);
void KM_Shutdown(void);
const char *KM_GetVersion(void);

const char *KM_LibraryScan(const char *root);
const char *KM_LibraryGetBooks(void);
const char *KM_LibraryGetBook(int64_t id);
const char *KM_LibraryUpdateMetadata(int64_t id, const char *title, const char *author);
const char *KM_LibraryDeleteBook(int64_t id);

const char *KM_ConvertBook(const char *input, const char *output, const char *format);
const char *KM_OperationGetStatus(const char *id);
const char *KM_OperationCancel(const char *id);
const char *KM_OperationList(void);

const char *KM_FilesystemList(const char *path);
const char *KM_SettingGet(const char *key);
const char *KM_SettingSet(const char *key, const char *value);

const char *KM_DeviceDiscover(void);
const char *KM_DeviceGetList(void);
const char *KM_DeviceGetInfo(int bus, int dev);
int KM_DeviceIsConnected(void);
const char *KM_DeviceListBooks(void);
const char *KM_DeviceTransferProgress(void);
const char *KM_DeviceCancelTransfer(void);
const char *KM_DeviceUploadBook(const char *localPath, uint32_t parentID, uint32_t storageID);
const char *KM_DeviceDownloadBook(uint32_t objectID, const char *localPath);
const char *KM_DeviceDeleteBook(uint32_t objectID);
const char *KM_DeviceMoveBook(uint32_t objectID, uint32_t storageID, uint32_t parentID);
const char *KM_DeviceCopyBook(uint32_t objectID, uint32_t storageID, uint32_t parentID);
const char *KM_DeviceCreateFolder(const char *name, uint32_t parentID, uint32_t storageID);
const char *KM_DeviceRenameBook(uint32_t objectID, const char *newName);

void KM_FreeMemory(void *ptr);

#ifdef __cplusplus
}
#endif

#endif
