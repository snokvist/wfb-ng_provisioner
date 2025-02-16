#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>      // for open()
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/wait.h>
#include <signal.h>

void flush_io() {
    fflush(NULL);
}

int main(int argc, char **argv) {
    // Defaults:
    int mode = 0;      // 0 = server (default), 1 = client
    int use_udp = 0;   // 0 = TCP (default), 1 = UDP
    int arg_offset = 1;

    // Parse optional flags (all flags start with "--")
    while (arg_offset < argc && strncmp(argv[arg_offset], "--", 2) == 0) {
        if (strcmp(argv[arg_offset], "--server") == 0) {
            mode = 0;
        } else if (strcmp(argv[arg_offset], "--client") == 0) {
            mode = 1;
        } else if (strcmp(argv[arg_offset], "--udp") == 0) {
            use_udp = 1;
        } else {
            fprintf(stderr, "Unknown flag: %s\n", argv[arg_offset]);
            exit(EXIT_FAILURE);
        }
        arg_offset++;
    }

    // We now require at least three more arguments: port, address, command
    if (argc - arg_offset < 3) {
        fprintf(stderr, "Usage: %s [--server|--client] [--udp] <port> <address> <command> [args...]\n", argv[0]);
        exit(EXIT_FAILURE);
    }
    int port = atoi(argv[arg_offset]);
    const char *ip = argv[arg_offset + 1];
    char **cmd_argv = &argv[arg_offset + 2];

    if (!use_udp) {
        /* ----- TCP MODE ----- */
        if (mode == 0) {
            /* TCP Server Mode */
            int listen_fd = socket(AF_INET, SOCK_STREAM, 0);
            if (listen_fd < 0) {
                perror("socket creation failed");
                exit(EXIT_FAILURE);
            }
            int opt = 1;
            if (setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) < 0) {
                perror("setsockopt failed");
                close(listen_fd);
                exit(EXIT_FAILURE);
            }
            struct sockaddr_in serv_addr;
            memset(&serv_addr, 0, sizeof(serv_addr));
            serv_addr.sin_family = AF_INET;
            serv_addr.sin_port = htons(port);
            serv_addr.sin_addr.s_addr = inet_addr(ip);
            if (bind(listen_fd, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
                perror("bind failed");
                close(listen_fd);
                exit(EXIT_FAILURE);
            }
            if (listen(listen_fd, 1) < 0) {
                perror("listen failed");
                close(listen_fd);
                exit(EXIT_FAILURE);
            }
            fprintf(stderr, "TCP server listening on %s:%d\n", ip, port);
            while (1) {
                struct sockaddr_in client_addr;
                socklen_t client_len = sizeof(client_addr);
                int conn_fd = accept(listen_fd, (struct sockaddr *)&client_addr, &client_len);
                if (conn_fd < 0) {
                    perror("accept failed");
                    continue;
                }
                fprintf(stderr, "Connection accepted\n");
                pid_t pid = fork();
                if (pid < 0) {
                    perror("fork failed");
                    close(conn_fd);
                    continue;
                }
                if (pid == 0) {
                    /* Child: dup connection onto stdin and stdout */
                    if (dup2(conn_fd, STDIN_FILENO) < 0 ||
                        dup2(conn_fd, STDOUT_FILENO) < 0) {
                        perror("dup2 failed");
                        close(conn_fd);
                        exit(EXIT_FAILURE);
                    }
                    close(conn_fd);
                    flush_io();
                    execvp(cmd_argv[0], cmd_argv);
                    perror("execvp failed");
                    exit(EXIT_FAILURE);
                } else {
                    close(conn_fd);
                    int status;
                    waitpid(pid, &status, 0);
                    fprintf(stderr, "Connection closed. Restarting listening.\n");
                }
            }
            close(listen_fd);
        } else {
            /* TCP Client Mode */
            while (1) {
                int sock_fd = socket(AF_INET, SOCK_STREAM, 0);
                if (sock_fd < 0) {
                    perror("socket creation failed");
                    exit(EXIT_FAILURE);
                }
                struct sockaddr_in serv_addr;
                memset(&serv_addr, 0, sizeof(serv_addr));
                serv_addr.sin_family = AF_INET;
                serv_addr.sin_port = htons(port);
                serv_addr.sin_addr.s_addr = inet_addr(ip);
                if (connect(sock_fd, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
                    perror("connect failed");
                    close(sock_fd);
                    sleep(1);
                    continue;
                }
                fprintf(stderr, "Connected to TCP server %s:%d\n", ip, port);
                pid_t pid = fork();
                if (pid < 0) {
                    perror("fork failed");
                    close(sock_fd);
                    exit(EXIT_FAILURE);
                }
                if (pid == 0) {
                    if (dup2(sock_fd, STDIN_FILENO) < 0 ||
                        dup2(sock_fd, STDOUT_FILENO) < 0) {
                        perror("dup2 failed");
                        close(sock_fd);
                        exit(EXIT_FAILURE);
                    }
                    close(sock_fd);
                    flush_io();
                    execvp(cmd_argv[0], cmd_argv);
                    perror("execvp failed");
                    exit(EXIT_FAILURE);
                } else {
                    close(sock_fd);
                    int status;
                    waitpid(pid, &status, 0);
                    fprintf(stderr, "Connection lost. Retrying in 1 second.\n");
                    sleep(1);
                }
            }
        }
    } else {
        /* ----- UDP MODE ----- */
        if (mode == 0) {
            /* UDP Server Mode:
             *  - Create a UDP socket bound to the given IP/port.
             *  - In an endless loop, fork a child process.
             *  - In the child, redirect its STDIN to come from a pipe (fed by UDP datagrams)
             *    and redirect STDOUT to /dev/null (dropping any output).
             *  - In the parent, receive UDP datagrams and write them into the pipe.
             */
            int udp_sock = socket(AF_INET, SOCK_DGRAM, 0);
            if (udp_sock < 0) {
                perror("UDP socket creation failed");
                exit(EXIT_FAILURE);
            }
            struct sockaddr_in serv_addr;
            memset(&serv_addr, 0, sizeof(serv_addr));
            serv_addr.sin_family = AF_INET;
            serv_addr.sin_port = htons(port);
            serv_addr.sin_addr.s_addr = inet_addr(ip);
            if (bind(udp_sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
                perror("UDP bind failed");
                close(udp_sock);
                exit(EXIT_FAILURE);
            }
            fprintf(stderr, "UDP server listening on %s:%d\n", ip, port);
            while (1) {
                int pipe_fd[2];
                if (pipe(pipe_fd) < 0) {
                    perror("pipe failed");
                    exit(EXIT_FAILURE);
                }
                pid_t pid = fork();
                if (pid < 0) {
                    perror("fork failed");
                    close(pipe_fd[0]);
                    close(pipe_fd[1]);
                    continue;
                }
                if (pid == 0) {
                    /* Child process: redirect STDIN from the pipe and drop STDOUT */
                    close(pipe_fd[1]); // close write end
                    if (dup2(pipe_fd[0], STDIN_FILENO) < 0) {
                        perror("dup2 failed");
                        exit(EXIT_FAILURE);
                    }
                    close(pipe_fd[0]);
                    int devnull = open("/dev/null", O_WRONLY);
                    if (devnull < 0) {
                        perror("open /dev/null failed");
                        exit(EXIT_FAILURE);
                    }
                    if (dup2(devnull, STDOUT_FILENO) < 0) {
                        perror("dup2 /dev/null failed");
                        exit(EXIT_FAILURE);
                    }
                    close(devnull);
                    flush_io();
                    execvp(cmd_argv[0], cmd_argv);
                    perror("execvp failed");
                    exit(EXIT_FAILURE);
                } else {
                    /* Parent process: read UDP datagrams and write them to the pipe */
                    close(pipe_fd[0]); // close read end
                    char buffer[4096];
                    ssize_t r;
                    while ((r = recvfrom(udp_sock, buffer, sizeof(buffer), 0, NULL, NULL)) > 0) {
                        ssize_t total_written = 0;
                        while (total_written < r) {
                            ssize_t w = write(pipe_fd[1], buffer + total_written, r - total_written);
                            if (w < 0) {
                                perror("write to pipe failed");
                                break;
                            }
                            total_written += w;
                        }
                        // Keep reading UDP packets regardless of write errors.
                    }
                    close(pipe_fd[1]);
                    int status;
                    waitpid(pid, &status, 0);
                    fprintf(stderr, "Child terminated, restarting UDP server child.\n");
                }
            }
            close(udp_sock);
        } else {
            /* UDP Client Mode:
             *  - Create a UDP socket and "connect" it to the server address.
             *  - In an endless loop, fork a child process.
             *  - In the child, drop STDIN (redirect from /dev/null) and redirect STDOUT
             *    to a pipe.
             *  - In the parent, read from the pipe and send the data via UDP, ignoring send errors.
             *    This way, even if the remote is not listening, the child's pipe remains open.
             */
            /* Ignore SIGPIPE so that send errors don't terminate the process */
            signal(SIGPIPE, SIG_IGN);

            int udp_sock = socket(AF_INET, SOCK_DGRAM, 0);
            if (udp_sock < 0) {
                perror("UDP socket creation failed");
                exit(EXIT_FAILURE);
            }
            struct sockaddr_in serv_addr;
            memset(&serv_addr, 0, sizeof(serv_addr));
            serv_addr.sin_family = AF_INET;
            serv_addr.sin_port = htons(port);
            serv_addr.sin_addr.s_addr = inet_addr(ip);
            if (connect(udp_sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
                perror("UDP connect failed");
                close(udp_sock);
                exit(EXIT_FAILURE);
            }
            fprintf(stderr, "UDP client connected to %s:%d\n", ip, port);
            while (1) {
                int pipe_fd[2];
                if (pipe(pipe_fd) < 0) {
                    perror("pipe failed");
                    exit(EXIT_FAILURE);
                }
                pid_t pid = fork();
                if (pid < 0) {
                    perror("fork failed");
                    close(pipe_fd[0]);
                    close(pipe_fd[1]);
                    continue;
                }
                if (pid == 0) {
                    /* Child process: drop STDIN and send command output to the pipe */
                    int devnull = open("/dev/null", O_RDONLY);
                    if (devnull < 0) {
                        perror("open /dev/null failed");
                        exit(EXIT_FAILURE);
                    }
                    if (dup2(devnull, STDIN_FILENO) < 0) {
                        perror("dup2 /dev/null failed");
                        exit(EXIT_FAILURE);
                    }
                    close(devnull);
                    close(pipe_fd[0]); // close read end
                    if (dup2(pipe_fd[1], STDOUT_FILENO) < 0) {
                        perror("dup2 pipe failed");
                        exit(EXIT_FAILURE);
                    }
                    close(pipe_fd[1]);
                    flush_io();
                    execvp(cmd_argv[0], cmd_argv);
                    perror("execvp failed");
                    exit(EXIT_FAILURE);
                } else {
                    /* Parent process: read from the pipe and send via UDP */
                    close(pipe_fd[1]); // close write end
                    char buffer[4096];
                    ssize_t r;
                    while ((r = read(pipe_fd[0], buffer, sizeof(buffer))) > 0) {
                        ssize_t total_sent = 0;
                        while (total_sent < r) {
#ifdef MSG_NOSIGNAL
                            ssize_t s = send(udp_sock, buffer + total_sent, r - total_sent, MSG_NOSIGNAL);
#else
                            ssize_t s = send(udp_sock, buffer + total_sent, r - total_sent, 0);
#endif
                            if (s < 0) {
                                perror("send failed");
                                /* Instead of breaking and closing the pipe (which would cause the child to see EOF),
                                 * simply drop the remainder of this packet.
                                 */
                                break;
                            }
                            total_sent += s;
                        }
                        /* Continue reading regardless of send errors */
                    }
                    close(pipe_fd[0]);
                    int status;
                    waitpid(pid, &status, 0);
                    fprintf(stderr, "Child terminated, restarting UDP client child.\n");
                    sleep(1);
                }
            }
            close(udp_sock);
        }
    }
    return 0;
}
