#include <errno.h>
#include <inttypes.h>
#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <time.h>

/* RUSAGE_INFO_V4 wakeup counters are cumulative; compare deltas over fixed windows. */

static void fail(const char *message) {
  fprintf(stderr, "process-wakeup-probe: %s\n", message);
  exit(1);
}

static double monotonic_seconds(void) {
  struct timespec value;
  if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) {
    fail("clock_gettime failed");
  }
  return (double)value.tv_sec + (double)value.tv_nsec / 1000000000.0;
}

static void read_usage(pid_t pid, struct rusage_info_v4 *usage) {
  memset(usage, 0, sizeof(*usage));
  if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)usage) != 0) {
    fprintf(stderr, "process-wakeup-probe: proc_pid_rusage failed for pid %d: %s\n", pid,
            strerror(errno));
    exit(2);
  }
}

static uint64_t checked_delta(uint64_t before, uint64_t after, const char *field) {
  if (after < before) {
    fprintf(stderr, "process-wakeup-probe: counter moved backwards: %s\n", field);
    exit(3);
  }
  return after - before;
}

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "usage: %s <pid> <duration-seconds>\n", argv[0]);
    return 64;
  }

  char *pid_end = NULL;
  char *duration_end = NULL;
  long parsed_pid = strtol(argv[1], &pid_end, 10);
  long parsed_duration = strtol(argv[2], &duration_end, 10);
  if (pid_end == argv[1] || *pid_end != '\0' || parsed_pid <= 0 || parsed_pid > INT32_MAX) {
    fail("invalid pid");
  }
  if (duration_end == argv[2] || *duration_end != '\0' || parsed_duration <= 0 ||
      parsed_duration > 86400) {
    fail("invalid duration");
  }

  pid_t pid = (pid_t)parsed_pid;
  struct rusage_info_v4 before;
  struct rusage_info_v4 after;
  read_usage(pid, &before);
  double started = monotonic_seconds();

  struct timespec remaining = {.tv_sec = parsed_duration, .tv_nsec = 0};
  while (nanosleep(&remaining, &remaining) != 0) {
    if (errno != EINTR) {
      fail("nanosleep failed");
    }
  }

  read_usage(pid, &after);
  double elapsed = monotonic_seconds() - started;
  if (!(elapsed > 0.0)) {
    fail("non-positive elapsed time");
  }

  uint64_t idle_delta = checked_delta(before.ri_pkg_idle_wkups, after.ri_pkg_idle_wkups,
                                      "ri_pkg_idle_wkups");
  uint64_t interrupt_delta = checked_delta(before.ri_interrupt_wkups, after.ri_interrupt_wkups,
                                           "ri_interrupt_wkups");
  uint64_t user_delta = checked_delta(before.ri_user_time, after.ri_user_time, "ri_user_time");
  uint64_t system_delta = checked_delta(before.ri_system_time, after.ri_system_time,
                                        "ri_system_time");

  printf("{\n");
  printf("  \"schemaVersion\": 1,\n");
  printf("  \"pid\": %d,\n", pid);
  printf("  \"durationSeconds\": %.6f,\n", elapsed);
  printf("  \"packageIdleWakeupsDelta\": %" PRIu64 ",\n", idle_delta);
  printf("  \"interruptWakeupsDelta\": %" PRIu64 ",\n", interrupt_delta);
  printf("  \"packageIdleWakeupsPerSecond\": %.9f,\n", (double)idle_delta / elapsed);
  printf("  \"interruptWakeupsPerSecond\": %.9f,\n", (double)interrupt_delta / elapsed);
  printf("  \"userTimeNanosecondsDelta\": %" PRIu64 ",\n", user_delta);
  printf("  \"systemTimeNanosecondsDelta\": %" PRIu64 "\n", system_delta);
  printf("}\n");
  return 0;
}
