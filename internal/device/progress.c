#include <stdint.h>
#include <libmtp.h>

extern int kmProgress(uint64_t sent, uint64_t total, void *data);

static int km_progress_trampoline(uint64_t const sent, uint64_t const total, void const * const data) {
    return kmProgress(sent, total, (void *)data);
}

int km_send_file_with_progress(LIBMTP_mtpdevice_t *device, const char *path,
                               LIBMTP_file_t *file, void *data) {
    return LIBMTP_Send_File_From_File(device, path, file, km_progress_trampoline, data);
}

int km_get_file_with_progress(LIBMTP_mtpdevice_t *device, uint32_t object_id,
                              const char *path, void *data) {
    return LIBMTP_Get_File_To_File(device, object_id, path, km_progress_trampoline, data);
}
