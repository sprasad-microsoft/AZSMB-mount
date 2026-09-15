#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define MOUNT_SCRIPT "/opt/microsoft/azsmb/mountscript.sh"

int main(int argc, char *argv[])
{
	(void)argc;

	unsetenv("BASH_ENV");
	unsetenv("ENV");
	unsetenv("LD_LIBRARY_PATH");
	unsetenv("LD_PRELOAD");
	unsetenv("AZSMB_AUTH_CONFIG_FILE");
	unsetenv("AZSMB_CIFS_UTILS_VERSION");
	unsetenv("AZSMB_CREDENTIAL_DIR");
	unsetenv("AZSMB_ENVIRONMENT");
	unsetenv("AZSMB_KERNEL_RELEASE");
	unsetenv("AZSMB_OS_RELEASE_FILE");
	setenv("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", 1);

	execv(MOUNT_SCRIPT, argv);
	perror("execv");
	return 1;
}