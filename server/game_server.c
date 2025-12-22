/*
 * Douglass The Keeper - Multiplayer UDP Server
 *
 * A simple UDP game server that handles multiple players.
 * Each client gets a dedicated thread for I/O processing.
 *
 * Compile: gcc -o game_server game_server.c -lpthread -lm
 * Run: ./game_server [port]
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <time.h>
#include <math.h>
#include <signal.h>
#include <errno.h>

#define DEFAULT_PORT 7777
#define MAX_PLAYERS 32
#define BUFFER_SIZE 1024
#define PLAYER_TIMEOUT_SEC 10
#define BROADCAST_INTERVAL_MS 50

// Player state flags
#define STATE_IDLE      0
#define STATE_WALKING   1
#define STATE_RUNNING   2
#define STATE_ATTACKING 3
#define STATE_BLOCKING  4
#define STATE_JUMPING   5

// Packet types
#define PKT_JOIN        1
#define PKT_LEAVE       2
#define PKT_UPDATE      3
#define PKT_WORLD_STATE 4
#define PKT_PING        5
#define PKT_PONG        6

#pragma pack(push, 1)

// Player position and state
typedef struct {
    uint32_t player_id;
    float pos_x, pos_y, pos_z;
    float rot_y;  // Rotation around Y axis
    uint8_t state;
    uint8_t combat_mode;  // 0 = unarmed, 1 = armed
    float health;
} PlayerData;

// Network packet header
typedef struct {
    uint8_t type;
    uint32_t player_id;
    uint32_t sequence;
} PacketHeader;

// Join packet (client -> server)
typedef struct {
    PacketHeader header;
    char player_name[32];
} JoinPacket;

// Update packet (client -> server)
typedef struct {
    PacketHeader header;
    PlayerData data;
} UpdatePacket;

// World state packet (server -> client)
typedef struct {
    PacketHeader header;
    uint8_t player_count;
    PlayerData players[MAX_PLAYERS];
} WorldStatePacket;

#pragma pack(pop)

// Player info stored on server
typedef struct {
    uint32_t player_id;
    char name[32];
    struct sockaddr_in addr;
    time_t last_seen;
    PlayerData data;
    int active;
    pthread_t thread;
} Player;

// Global server state
static int server_socket = -1;
static Player players[MAX_PLAYERS];
static pthread_mutex_t players_mutex = PTHREAD_MUTEX_INITIALIZER;
static volatile int running = 1;
static uint32_t next_player_id = 1;

// Original spawn point
static float spawn_x = 0.0f;
static float spawn_y = 0.0f;
static float spawn_z = 0.0f;

void signal_handler(int sig) {
    printf("\nShutting down server...\n");
    running = 0;
}

// Generate random spawn position within 50m of original spawn
void generate_spawn_position(float *x, float *y, float *z) {
    float angle = ((float)rand() / RAND_MAX) * 2.0f * M_PI;
    float distance = ((float)rand() / RAND_MAX) * 50.0f;

    *x = spawn_x + cos(angle) * distance;
    *y = spawn_y;  // Keep same Y level
    *z = spawn_z + sin(angle) * distance;
}

// Find player by address
Player* find_player_by_addr(struct sockaddr_in *addr) {
    for (int i = 0; i < MAX_PLAYERS; i++) {
        if (players[i].active &&
            players[i].addr.sin_addr.s_addr == addr->sin_addr.s_addr &&
            players[i].addr.sin_port == addr->sin_port) {
            return &players[i];
        }
    }
    return NULL;
}

// Find player by ID
Player* find_player_by_id(uint32_t id) {
    for (int i = 0; i < MAX_PLAYERS; i++) {
        if (players[i].active && players[i].player_id == id) {
            return &players[i];
        }
    }
    return NULL;
}

// Find free player slot
int find_free_slot() {
    for (int i = 0; i < MAX_PLAYERS; i++) {
        if (!players[i].active) {
            return i;
        }
    }
    return -1;
}

// Count active players
int count_active_players() {
    int count = 0;
    for (int i = 0; i < MAX_PLAYERS; i++) {
        if (players[i].active) count++;
    }
    return count;
}

// Broadcast world state to all players
void broadcast_world_state() {
    WorldStatePacket packet;
    memset(&packet, 0, sizeof(packet));

    packet.header.type = PKT_WORLD_STATE;
    packet.header.sequence = (uint32_t)time(NULL);

    pthread_mutex_lock(&players_mutex);

    int count = 0;
    for (int i = 0; i < MAX_PLAYERS && count < MAX_PLAYERS; i++) {
        if (players[i].active) {
            packet.players[count] = players[i].data;
            count++;
        }
    }
    packet.player_count = count;

    // Send to all active players
    for (int i = 0; i < MAX_PLAYERS; i++) {
        if (players[i].active) {
            sendto(server_socket, &packet, sizeof(packet), 0,
                   (struct sockaddr*)&players[i].addr, sizeof(players[i].addr));
        }
    }

    pthread_mutex_unlock(&players_mutex);
}

// Handle join request
void handle_join(JoinPacket *pkt, struct sockaddr_in *client_addr) {
    pthread_mutex_lock(&players_mutex);

    // Check if already connected
    Player *existing = find_player_by_addr(client_addr);
    if (existing) {
        printf("Player %s reconnected (ID: %u)\n", existing->name, existing->player_id);
        existing->last_seen = time(NULL);
        pthread_mutex_unlock(&players_mutex);
        return;
    }

    // Find free slot
    int slot = find_free_slot();
    if (slot < 0) {
        printf("Server full, rejecting player %s\n", pkt->player_name);
        pthread_mutex_unlock(&players_mutex);
        return;
    }

    // Initialize new player
    Player *player = &players[slot];
    memset(player, 0, sizeof(Player));

    player->player_id = next_player_id++;
    strncpy(player->name, pkt->player_name, sizeof(player->name) - 1);
    player->addr = *client_addr;
    player->last_seen = time(NULL);
    player->active = 1;

    // Set initial player data
    player->data.player_id = player->player_id;
    generate_spawn_position(&player->data.pos_x, &player->data.pos_y, &player->data.pos_z);
    player->data.rot_y = 0;
    player->data.state = STATE_IDLE;
    player->data.combat_mode = 1;  // Armed by default
    player->data.health = 100.0f;

    printf("Player %s joined (ID: %u) at position (%.1f, %.1f, %.1f) - Total players: %d\n",
           player->name, player->player_id,
           player->data.pos_x, player->data.pos_y, player->data.pos_z,
           count_active_players());

    // Send initial world state to new player
    pthread_mutex_unlock(&players_mutex);
    broadcast_world_state();
}

// Handle player update
void handle_update(UpdatePacket *pkt, struct sockaddr_in *client_addr) {
    pthread_mutex_lock(&players_mutex);

    Player *player = find_player_by_id(pkt->header.player_id);
    if (!player) {
        pthread_mutex_unlock(&players_mutex);
        return;
    }

    // Verify address matches
    if (player->addr.sin_addr.s_addr != client_addr->sin_addr.s_addr ||
        player->addr.sin_port != client_addr->sin_port) {
        pthread_mutex_unlock(&players_mutex);
        return;
    }

    // Update player data
    player->data = pkt->data;
    player->data.player_id = player->player_id;  // Ensure ID is preserved
    player->last_seen = time(NULL);

    pthread_mutex_unlock(&players_mutex);
}

// Handle player leave
void handle_leave(PacketHeader *hdr, struct sockaddr_in *client_addr) {
    pthread_mutex_lock(&players_mutex);

    Player *player = find_player_by_id(hdr->player_id);
    if (player) {
        printf("Player %s left (ID: %u)\n", player->name, player->player_id);
        player->active = 0;
    }

    pthread_mutex_unlock(&players_mutex);
    broadcast_world_state();
}

// Cleanup timed out players
void cleanup_inactive_players() {
    time_t now = time(NULL);

    pthread_mutex_lock(&players_mutex);

    for (int i = 0; i < MAX_PLAYERS; i++) {
        if (players[i].active && (now - players[i].last_seen) > PLAYER_TIMEOUT_SEC) {
            printf("Player %s timed out (ID: %u)\n", players[i].name, players[i].player_id);
            players[i].active = 0;
        }
    }

    pthread_mutex_unlock(&players_mutex);
}

// Broadcast thread - sends world state periodically
void* broadcast_thread(void *arg) {
    while (running) {
        broadcast_world_state();
        usleep(BROADCAST_INTERVAL_MS * 1000);

        // Cleanup every second
        static int cleanup_counter = 0;
        if (++cleanup_counter >= (1000 / BROADCAST_INTERVAL_MS)) {
            cleanup_inactive_players();
            cleanup_counter = 0;
        }
    }
    return NULL;
}

// Main receive loop
void* receive_thread(void *arg) {
    char buffer[BUFFER_SIZE];
    struct sockaddr_in client_addr;
    socklen_t addr_len = sizeof(client_addr);

    while (running) {
        ssize_t recv_len = recvfrom(server_socket, buffer, BUFFER_SIZE, 0,
                                     (struct sockaddr*)&client_addr, &addr_len);

        if (recv_len < 0) {
            if (errno == EINTR) continue;
            perror("recvfrom failed");
            continue;
        }

        if (recv_len < sizeof(PacketHeader)) {
            continue;  // Invalid packet
        }

        PacketHeader *header = (PacketHeader*)buffer;

        switch (header->type) {
            case PKT_JOIN:
                if (recv_len >= sizeof(JoinPacket)) {
                    handle_join((JoinPacket*)buffer, &client_addr);
                }
                break;

            case PKT_UPDATE:
                if (recv_len >= sizeof(UpdatePacket)) {
                    handle_update((UpdatePacket*)buffer, &client_addr);
                }
                break;

            case PKT_LEAVE:
                handle_leave(header, &client_addr);
                break;

            case PKT_PING:
                // Respond with pong
                {
                    PacketHeader pong;
                    pong.type = PKT_PONG;
                    pong.player_id = header->player_id;
                    pong.sequence = header->sequence;
                    sendto(server_socket, &pong, sizeof(pong), 0,
                           (struct sockaddr*)&client_addr, addr_len);
                }
                break;

            default:
                printf("Unknown packet type: %d\n", header->type);
                break;
        }
    }
    return NULL;
}

int main(int argc, char *argv[]) {
    int port = DEFAULT_PORT;

    if (argc > 1) {
        port = atoi(argv[1]);
    }

    // Initialize random seed
    srand(time(NULL));

    // Setup signal handler
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    // Create UDP socket
    server_socket = socket(AF_INET, SOCK_DGRAM, 0);
    if (server_socket < 0) {
        perror("Failed to create socket");
        return 1;
    }

    // Allow address reuse
    int opt = 1;
    setsockopt(server_socket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    // Bind to port
    struct sockaddr_in server_addr;
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(port);

    if (bind(server_socket, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
        perror("Failed to bind socket");
        close(server_socket);
        return 1;
    }

    // Initialize players array
    memset(players, 0, sizeof(players));

    printf("===========================================\n");
    printf("  Douglass The Keeper - Game Server\n");
    printf("===========================================\n");
    printf("Listening on UDP port %d\n", port);
    printf("Max players: %d\n", MAX_PLAYERS);
    printf("Broadcast interval: %d ms\n", BROADCAST_INTERVAL_MS);
    printf("Player timeout: %d seconds\n", PLAYER_TIMEOUT_SEC);
    printf("Press Ctrl+C to stop\n");
    printf("===========================================\n\n");

    // Start broadcast thread
    pthread_t broadcast_tid;
    pthread_create(&broadcast_tid, NULL, broadcast_thread, NULL);

    // Start receive thread (or run in main thread)
    receive_thread(NULL);

    // Cleanup
    pthread_join(broadcast_tid, NULL);
    close(server_socket);

    printf("Server stopped.\n");
    return 0;
}
