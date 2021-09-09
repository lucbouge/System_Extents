//
// Created by Mario Wolczko on 9/9/21.
//

#ifndef EXTENTS_SHARING_H
#define EXTENTS_SHARING_H

// an extent with its sharing info
typedef struct sh_ext sh_ext;
struct sh_ext {
    off_t p;         // physical offset on device
    off_t len;
    list *owners;    // the original extent*s from whence it came
};

extern list *shared; // list of sh_ext*

extern unsigned total_unshared;
extern unsigned max_n_shared;

void find_shares();

#endif //EXTENTS_SHARING_H
