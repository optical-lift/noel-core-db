/* Fictional runner-boundary probe. Never reuse as a product/security proof. */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static void need(int ok, const char *why) {
    if (!ok) { fprintf(stderr, "REFUSE: %s\n", why); exit(1); }
}
static int peer(const char *ip) {
    struct sockaddr_in a = {.sin_family=AF_INET,.sin_port=htons(18080)};
    need(inet_pton(AF_INET,ip,&a.sin_addr)==1,"invalid synthetic endpoint");
    int fd=socket(AF_INET,SOCK_STREAM|SOCK_NONBLOCK,0);
    need(fd>=0,"socket unavailable");
    if (connect(fd,(struct sockaddr*)&a,sizeof(a)) && errno!=EINPROGRESS) {close(fd);return -1;}
    struct pollfd p={.fd=fd,.events=POLLOUT};
    int error=0; socklen_t n=sizeof(error);
    if(poll(&p,1,700)<=0 || getsockopt(fd,SOL_SOCKET,SO_ERROR,&error,&n) || error) {close(fd);return -1;}
    return fd;
}
static void allow(const char *ip) {
    int fd=-1;
    for(int j=0;j<15 && fd<0;j++) {fd=peer(ip);if(fd<0)usleep(100000);}
    need(fd>=0,"admitted fictional service unreachable");
    struct pollfd p={.fd=fd,.events=POLLIN};char b[16]={0};
    need(poll(&p,1,1000)>0 && read(fd,b,sizeof(b))==2 && !memcmp(b,"OK",2),"fictional service receipt mismatch");close(fd);
}
static void deny(const char *ip) {int fd=peer(ip);if(fd>=0)close(fd);need(fd<0,"unrelated fictional service reachable");}
static void serve(void) {
    signal(SIGPIPE,SIG_IGN);
    int fd=socket(AF_INET,SOCK_STREAM,0),one=1;
    need(fd>=0,"server socket");setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&one,sizeof(one));
    struct sockaddr_in a={.sin_family=AF_INET,.sin_port=htons(18080),.sin_addr.s_addr=htonl(INADDR_ANY)};
    need(bind(fd,(struct sockaddr*)&a,sizeof(a))==0 && listen(fd,8)==0,"server bind/listen");
    for(;;){int c=accept(fd,NULL,NULL);if(c>=0){ssize_t sent=write(c,"OK",2);close(c);if(sent!=2&&sent!=-1)exit(1);}else if(errno!=EINTR)exit(1);}
}
static void status(const char *key,const char *value) {
    FILE *f=fopen("/proc/self/status","r");need(f!=NULL,"proc status missing");
    char line[512];int found=0;
    while(fgets(line,sizeof(line),f))if(!strncmp(line,key,strlen(key))){char *v=line+strlen(key);v+=strspn(v," \t");v[strcspn(v,"\r\n")]=0;found=!strcmp(v,value);break;}
    fclose(f);need(found,"process confinement status mismatch");
}
static void no_default_route(void) {
    FILE *f=fopen("/proc/net/route","r");need(f!=NULL,"route table missing");char line[512],iface[64],dest[16],gw[16],flags[16];
    need(fgets(line,sizeof(line),f)!=NULL,"route table header missing");
    while(fgets(line,sizeof(line),f))if(sscanf(line,"%63s %15s %15s %15s",iface,dest,gw,flags)==4)need(strcmp(dest,"00000000")!=0,"default IPv4 route present");
    fclose(f);
}
int main(int argc,char **argv) {
    if(argc==2&&!strcmp(argv[1],"serve")){serve();return 1;}
    if(argc==3&&!strcmp(argv[1],"allow")){allow(argv[2]);return 0;}
    if(argc==2&&!strcmp(argv[1],"fail"))return 42;
    need(argc==5&&!strcmp(argv[1],"probe"),"invalid fixed probe arguments");
    need(getuid()==65534&&geteuid()==65534&&getgid()==65534,"not unprivileged test user");
    status("NoNewPrivs:","1");status("CapEff:","0000000000000000");status("Seccomp:","2");
    const char *env[]={"GITHUB_ENV","GITHUB_OUTPUT","GITHUB_TOKEN","NOEL_CORE_DATABASE_URL","DATABASE_URL","SUPABASE_SERVICE_ROLE_KEY","SYNTHETIC_HOST_SECRET"};
    for(size_t j=0;j<sizeof(env)/sizeof(env[0]);j++)need(getenv(env[j])==NULL,"host environment inherited");
    need(access(argv[4],F_OK)!=0,"host marker visible");
    need(access("/var/run/docker.sock",F_OK)!=0&&access("/run/docker.sock",F_OK)!=0,"Docker socket visible");
    int fd=open("/admitted/fixture.txt",O_RDONLY);char b[16]={0};need(fd>=0&&read(fd,b,sizeof(b))==8&&!memcmp(b,"fiction\n",8),"admitted bytes unavailable");close(fd);
    fd=open("/admitted/fixture.txt",O_WRONLY);need(fd<0,"admitted file writable");
    fd=open("/admitted/extra",O_WRONLY|O_CREAT|O_EXCL,0600);need(fd<0,"admitted directory writable");
    fd=open("/unexpected",O_WRONLY|O_CREAT|O_EXCL,0600);need(fd<0,"root filesystem writable");
    fd=open("/tmp/scratch",O_WRONLY|O_CREAT|O_EXCL,0600);need(fd>=0,"bounded scratch unavailable");close(fd);
    no_default_route();allow(argv[2]);deny(argv[3]);
    puts("PASS fictional process, filesystem, environment and network boundaries");return 0;
}
