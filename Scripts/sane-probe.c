/*
 * sane-probe.c — tiny smoke-test probe for Scripts/smoke-sane.sh.
 *
 * Calls sane_init + sane_get_devices against the vendored libsane and prints
 * what it finds. Exit codes:
 *   0 — sane_init succeeded, and (unless SANE_PROBE_SKIP_DEVICE_CHECK is set)
 *       an hp5590: device was found.
 *   1 — sane_init or sane_get_devices failed.
 *   2 — sane_init succeeded but no hp5590: device was found (device check
 *       not skipped).
 */

#include <sane/sane.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    SANE_Int version = 0;
    SANE_Status st = sane_init(&version, NULL);
    if (st != SANE_STATUS_GOOD) {
        fprintf(stderr, "sane_init failed: %s\n", sane_strstatus(st));
        return 1;
    }
    printf("sane_init OK, version_code=%d\n", version);

    const SANE_Device **devices = NULL;
    st = sane_get_devices(&devices, SANE_FALSE);
    if (st != SANE_STATUS_GOOD) {
        fprintf(stderr, "sane_get_devices failed: %s\n", sane_strstatus(st));
        sane_exit();
        return 1;
    }

    int found_hp5590 = 0;
    for (int i = 0; devices[i] != NULL; i++) {
        printf("device[%d]: name=%s vendor=%s model=%s type=%s\n", i, devices[i]->name,
               devices[i]->vendor, devices[i]->model, devices[i]->type);
        if (devices[i]->name != NULL && strncmp(devices[i]->name, "hp5590:", 7) == 0) {
            found_hp5590 = 1;
        }
    }

    sane_exit();

    const char *skip = getenv("SANE_PROBE_SKIP_DEVICE_CHECK");
    if (skip != NULL && skip[0] != '\0' && strcmp(skip, "0") != 0) {
        printf("SANE_PROBE_SKIP_DEVICE_CHECK set, skipping device assertion\n");
        return 0;
    }

    if (found_hp5590) {
        printf("FOUND hp5590 device\n");
        return 0;
    }
    printf("NO hp5590 device found\n");
    return 2;
}
