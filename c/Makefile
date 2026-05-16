CC     = clang
CFLAGS = -shared -fPIC -O2 -I$(shell llvm-config --includedir)
LIBS   = $(shell llvm-config --ldflags) -lclang
OUT    = ../lua/memlay/libmemlay.so

libmemlay.so: layout.c parse.c memlay.h
	$(CC) $(CFLAGS) $(LIBS) -o $(OUT) layout.c parse.c

clean:
	rm -f $(OUT)
