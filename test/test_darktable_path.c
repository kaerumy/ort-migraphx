/* test_darktable_path.c — mimic darktable 5.6.2's ORT load path:
 * dlopen the exact versioned file, then request C API v24 (the version
 * darktable was built against) and list providers.
 * ORT's C API struct is additive (new functions appended at the end), so a
 * v24 OrtApi pointer can be used through the v31 struct layout for any
 * member that exists in v24.
 * usage: ./test_darktable_path /path/to/libonnxruntime.so.1.31.0
 */
#include <onnxruntime_c_api.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: %s <libonnxruntime.so.X.Y.Z>\n", argv[0]); return 2; }
  void *h = dlopen(argv[1], RTLD_LAZY | RTLD_LOCAL);
  if (!h) { fprintf(stderr, "dlopen failed: %s\n", dlerror()); return 1; }
  printf("dlopen OK: %s\n", argv[1]);

  const OrtApiBase *(*getbase)(void) =
      (const OrtApiBase *(*)(void))dlsym(h, "OrtGetApiBase");
  if (!getbase) { fprintf(stderr, "OrtGetApiBase symbol not found\n"); return 1; }
  const OrtApiBase *base = getbase();
  printf("library version string: %s\n", base->GetVersionString());

  /* darktable 5.6.2 was built against ORT 1.24 -> requests API version 24 */
  const OrtApi *api24 = (const OrtApi *)base->GetApi(24);
  if (!api24) { printf("GetApi(24) [darktable's version]: FAILED (incompatible!)\n"); return 1; }
  printf("GetApi(24) [darktable's version]: OK\n");

  char **provs = NULL;
  int n = 0;
  OrtStatus *st = api24->GetAvailableProviders(&provs, &n);
  if (st) {
    printf("GetAvailableProviders error: %s\n", api24->GetErrorMessage(st));
    api24->ReleaseStatus(st);
    return 1;
  }
  printf("providers (%d):\n", n);
  int has_mgx = 0;
  for (int i = 0; i < n; i++) {
    printf("  - %s\n", provs[i]);
    if (provs[i] && strstr(provs[i], "MIGraphX")) has_mgx = 1;
  }
  (void)api24->ReleaseAvailableProviders(provs, n);
  printf(has_mgx ? "MIGraphX provider: YES\n" : "MIGraphX provider: NO\n");
  return has_mgx ? 0 : 1;
}
