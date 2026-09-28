// Loads the shared library built by `--trim=safe` and calls its
// `trim_check_run` entry point, exiting with its return code. Compiling
// cleanly under `--trim=safe` only proves the trim verifier accepted the
// call graph; this catches bugs the verifier can't, like a runtime error in
// the check functions themselves.
#include <dlfcn.h>
#include <stdio.h>

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <path-to-trimcheck-shared-library>\n", argv[0]);
        return 1;
    }

    void *handle = dlopen(argv[1], RTLD_NOW);
    if (!handle) {
        fprintf(stderr, "dlopen failed: %s\n", dlerror());
        return 1;
    }

    int (*trim_check_run)(void) = dlsym(handle, "trim_check_run");
    if (!trim_check_run) {
        fprintf(stderr, "dlsym failed: %s\n", dlerror());
        return 1;
    }

    return trim_check_run();
}
