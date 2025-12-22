# Douglass The Keeper - Game Server Makefile

CC = gcc
CFLAGS = -Wall -Wextra -O2
LDFLAGS = -lpthread -lm

TARGET = game_server
SRC = game_server.c

.PHONY: all clean install

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f $(TARGET)

install: $(TARGET)
	cp $(TARGET) /usr/local/bin/

# Run with default port
run: $(TARGET)
	./$(TARGET)

# Run with custom port
run-port: $(TARGET)
	./$(TARGET) $(PORT)
