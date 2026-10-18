/* test_ort_mgx.c — smoke test for ONNXRuntime + MIGraphX EP (C API v31)
 * usage: ./test_ort_mgx <model.onnx> <x_input.bin> <y_expected.bin> <n_floats>
 * Exit 0 = inference ran and output matches; prints provider status.
 */
#include <onnxruntime_c_api.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const OrtApi *ort = NULL;
static int failures = 0;

static int check(OrtStatus *st, const char *what) {
  if (!st) return 0;
  fprintf(stderr, "ORT ERROR [%s]: %s\n", what, ort->GetErrorMessage(st));
  ort->ReleaseStatus(st);
  return 1;
}

static float *read_floats(const char *path, long *n_out) {
  FILE *f = fopen(path, "rb");
  if (!f) { fprintf(stderr, "cannot open %s\n", path); return NULL; }
  fseek(f, 0, SEEK_END);
  long n = ftell(f) / (long)sizeof(float);
  fseek(f, 0, SEEK_SET);
  float *v = malloc(n * sizeof(float));
  if (fread(v, sizeof(float), n, f) != (size_t)n) { fprintf(stderr, "short read %s\n", path); return NULL; }
  fclose(f);
  *n_out = n;
  return v;
}

int main(int argc, char **argv) {
  if (argc != 5) {
    fprintf(stderr, "usage: %s model.onnx x_input.bin y_expected.bin n_floats\n", argv[0]);
    return 2;
  }
  long n, n_exp;
  float *x = read_floats(argv[2], &n);
  float *yexp = read_floats(argv[3], &n_exp);
  if (!x || !yexp) return 2;
  long ne = atol(argv[4]);

  ort = OrtGetApiBase()->GetApi(ORT_API_VERSION);
  OrtEnv *env = NULL;
  OrtSessionOptions *so = NULL;
  OrtSession *sess = NULL;

  if (check(ort->CreateEnv(ORT_LOGGING_LEVEL_VERBOSE, "mgx-test", &env), "CreateEnv")) return 1;

  /* 1) available providers */
  char **avail = NULL;
  int navail = 0;
  check(ort->GetAvailableProviders(&avail, &navail), "GetAvailableProviders");
  printf("available providers (%d):\n", navail);
  int has_migraphx = 0;
  for (int i = 0; i < navail; i++) {
    printf("  - %s\n", avail[i]);
    if (avail[i] && strstr(avail[i], "MIGraphX")) has_migraphx = 1;
  }
  ort->ReleaseAvailableProviders(avail, navail);
  printf("MIGraphX EP registered: %s\n", has_migraphx ? "YES" : "NO");

  /* 2) session with MIGraphX EP (EP init probes the GPU; failure = error here) */
  check(ort->CreateSessionOptions(&so), "CreateSessionOptions");
  if (check(ort->SessionOptionsAppendExecutionProvider_MIGraphX(so, 0), "AppendExecutionProvider_MIGraphX")) return 1;
  if (check(ort->CreateSession(env, argv[1], so, &sess), "CreateSession")) return 1;
  printf("session created with MIGraphX EP appended (device 0)\n");

  /* 3) run inference */
  OrtMemoryInfo *mem = NULL;
  check(ort->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &mem), "CreateCpuMemoryInfo");
  OrtValue *input = NULL, *output = NULL;
  int64_t shape[] = {1, ne};
  check(ort->CreateTensorWithDataAsOrtValue(mem, x, ne * sizeof(float), shape, 2,
                                            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &input), "CreateTensor");
  const char *names_in[] = {"x"};
  const char *names_out[] = {"y"};
  const OrtValue *inputs_arr[] = {input};
  OrtValue *outputs_arr[] = {NULL};
  if (check(ort->Run(sess, NULL, names_in, inputs_arr, 1, names_out, 1, outputs_arr), "Run")) return 1;
  output = outputs_arr[0];

  float *y = malloc(ne * sizeof(float));
  check(ort->GetTensorMutableData(output, (void **)&y), "GetTensorMutableData");
  float maxerr = 0;
  for (long i = 0; i < ne; i++) {
    float e = fabsf(y[i] - yexp[i]);
    if (e > maxerr) maxerr = e;
  }
  printf("output:  ");
  for (long i = 0; i < ne; i++) printf(" %.5f", y[i]);
  printf("\nexpected:");
  for (long i = 0; i < ne; i++) printf(" %.5f", yexp[i]);
  printf("\nmax error: %g\n", maxerr);
  printf(maxerr < 1e-4f ? "RESULT: PASS\n" : "RESULT: FAIL\n");
  failures = maxerr >= 1e-4f;

  ort->ReleaseValue(input);
  ort->ReleaseValue(output);
  ort->ReleaseMemoryInfo(mem);
  ort->ReleaseSession(sess);
  ort->ReleaseSessionOptions(so);
  ort->ReleaseEnv(env);
  return failures;
}
