
SRCS := stringtest.c myroutines.S
CFLAGS := -O3 -fno-builtin -static

stringtest: $(SRCS)
	$(CC) $(CFLAGS) $(SRCS) -o $@

clean:
	rm stringtest
