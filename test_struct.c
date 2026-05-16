#include <stdint.h>
#include <stdbool.h>

struct Single {
    int x;
};

struct AlreadyOptimal {
    double a;
    int    b;
    short  c;
    char   d;
};

struct ClassicBad {
    char x;
    int  n;
    char flag;
};

struct AllChar {
    char a;
    char b;
    char c;
    char d;
};

struct AllInt {
    int a;
    int b;
    int c;
};

struct DoubleDominated {
    char   a;
    double b;
    char   c;
    int    d;
    char   e;
};

struct ShortMix {
    char  a;
    short b;
    char  c;
    short d;
    char  e;
};

struct WorstCase {
    char   a;
    short  b;
    int    c;
    double d;
};

struct BestCase {
    double a;
    int    b;
    short  c;
    char   d;
};

struct WithPointers {
    char  a;
    int  *p;
    char  b;
    void *q;
    short c;
};

struct PointerMix {
    int   x;
    char *str;
    char  flag;
    int   y;
};

struct ManyFields {
    char   a;
    short  b;
    char   c;
    int    d;
    char   e;
    short  f;
    char   g;
    double h;
};

struct WithArrays {
    char a;
    int  arr[100];
    char b;
    char buf[3];
};

struct Uint8Mix {
    uint8_t  a;
    uint32_t b;
    uint8_t  c;
    uint16_t d;
    uint8_t  e;
    uint64_t f;
};

struct Uint8Optimal {
    uint64_t a;
    uint32_t b;
    uint16_t c;
    uint8_t  d;
    uint8_t  e;
};

struct NoPadding {
    int   a;
    int   b;
    short c;
    short d;
    char  e;
    char  f;
    char  g;
    char  h;
};

struct TrailingPad {
    short a;
    char  b;
};

struct OneByte {
    char x;
};

struct TwoBytes {
    char x;
    char y;
};

struct PacketHeader {
    uint8_t  version;
    uint8_t  type;
    uint16_t length;
    uint32_t sequence;
    uint32_t ack;
    uint16_t window;
    uint16_t checksum;
};

struct BadPacket {
    uint8_t  version;
    uint32_t sequence;
    uint8_t  type;
    uint32_t ack;
    uint16_t length;
    uint8_t  flags;
    uint16_t checksum;
};

struct RegisterMap {
    uint8_t  status;
    uint32_t control;
    uint8_t  irq_mask;
    uint32_t data;
    uint16_t threshold;
    uint8_t  mode;
};

struct BoolMix {
    bool   flag_a;
    int    value;
    bool   flag_b;
    double data;
    bool   flag_c;
};

struct MaxAlignSandwich {
    char   a;
    char   b;
    char   c;
    double d;
    char   e;
    char   f;
    char   g;
};

struct AlternatingBad {
    char a;
    int  b;
    char c;
    int  d;
    char e;
    int  f;
    char g;
    int  h;
};

struct AllDoubles {
    double a;
    double b;
    double c;
};

typedef struct {
    char  x;
    int   n;
    char  flag;
} Foo;

typedef struct {
    double a;
    char   g;
    int    c;
    char   d;
    short  e;
} Large;

struct Node {
    int   data;
    struct Node *next;
};


struct DNode {
    struct DNode *prev;
    struct DNode *next;
    int           data;
    int           id;
};

// with metadata — common in allocators
struct NodeMeta {
    struct NodeMeta *next;
    int              data;
    char             color;   // red-black tree style
    char             marked;
    short            height;  // skip list style
};

struct TNode {
    char tag;
    struct Node  *next;
    char flags;
    int value;
    char visited;
    double weight;
    struct Node *prev;
    short depth;
};
