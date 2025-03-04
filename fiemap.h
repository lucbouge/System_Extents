// Functions to return extent info from the filesystem.

#include <stdbool.h>
#include "extents.h"

// TODO: Use a libc function. Also, take care of the computation order
// https://www.gnu.org/software/libc/manual/html_node/Rounding-Functions.html
// #define roundDown(a, b) ((a) / (b) * (b))
#define roundDown(a, b) (floor((a) / (b)))


extern void flags2str(unsigned flags, char *s, size_t n, bool sharing);
extern void get_extents(fileinfo *ip, off_t max_len);
extern bool flags_are_sane(unsigned flags);
