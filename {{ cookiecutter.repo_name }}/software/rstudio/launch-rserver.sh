#!/bin/sh

# Load variables for bind_path, singularity_image, IP_WORKSTATION, rstudio_home, project_home
cd "${0%/*}" # Move to which this script is located. Required for the source command to work always
source ../../.project_settings.sh

#-------------------------------------------------------------------------
# DECLARE PATH VARIABLES
#-------------------------------------------------------------------------
# Paths to bind (for singularity exec command, --bind flag)
bind_path=${bind_path}

# Path of the singularity image to run rstudio-server
singularity_image=${singularity_image}

# IP of workstation/cluster to connect
IP_WORKSTATION=${IP_WORKSTATION}

# Define the path where R packages will be installed
r_version={{cookiecutter.r_version}}
rstudio_home=${rstudio_home}
echo $rstudio_home
# Define project home dir
project_home=${project_home}

#-------------------------------------------------------------------------
# CREATE RLIB FOLDER AND RENVIRON
#-------------------------------------------------------------------------
r_packages="${rstudio_home}/Rstudio-${r_version}-lib"
mkdir -p ${r_packages}

# User-installed R packages go into their custom home directory
# Add also user-installed R packages into R_LIBS to force R to load those packages over those in the singularity image.
if [ ! -e ${project_home}/.Renviron ]
then
  printf '\nNOTE: creating ~/.Renviron file\n\n'
  echo "R_LIBS_USER=${r_packages}" >> ${project_home}/.Renviron
  echo "R_LIBS=${r_packages}:/usr/local/lib/R/site-library:/usr/local/lib/R/library:/usr/lib/R/library" >> ${project_home}/.Renviron
fi


#-------------------------------------------------------------------------
# SET VARIABLES TO RUN SERVER
#-------------------------------------------------------------------------
export SINGULARITYENV_USER=$(id -un) # same as whoami
export SINGULARITYENV_PASSWORD=$(openssl rand -base64 15)
# get unused socket per https://unix.stackexchange.com/a/132524
# tiny race condition between the python & singularity commands
readonly PORT=$(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
cat 1>&2 <<END
1. SSH tunnel from your workstation using the following command:

   ssh -N -L 8787:${HOSTNAME}:${PORT} ${SINGULARITYENV_USER}@${IP_WORKSTATION}

   and point your web browser to http://localhost:8787

2. log in to RStudio Server using the following credentials:

   user: ${SINGULARITYENV_USER}
   password: ${SINGULARITYENV_PASSWORD}

When done using RStudio Server, terminate the job by:

1. Exit the RStudio Session ("power" button in the top right corner of the RStudio window)
END

#-------------------------------------------------------------------------
# FIX PERMISSION PROBLEMS WITH ROCKER RSTUDIO 1.4 IMAGES
#-------------------------------------------------------------------------
##NOTE##
# This is a local drive location I can write, you should be able
# to just set to a subfolder of your HPC home/scratch directory
export TMPDIR="${rstudio_home}/rstudio-tmp"

# Create custom tmp dir to store secure-cookie-key. Otherwise it will be stored in /tmp and other users won't be able to 
# overwrite it
mkdir -p "$TMPDIR/tmp/rstudio-server"
uuidgen > "$TMPDIR/tmp/rstudio-server/secure-cookie-key"
chmod 0600 "$TMPDIR/tmp/rstudio-server/secure-cookie-key"

mkdir -p "$TMPDIR/run"
mkdir -p "$TMPDIR/var-lib-rstudio-server"

printf 'provider=sqlite\ndirectory=/var/lib/rstudio-server\n' > $TMPDIR/database.conf

# Also bind data directory on the host into the Singularity container.
# By default the only host file systems mounted within the container are $HOME, /tmp, /proc, /sys, and /dev.


#-------------------------------------------------------------------------
# FORCE CHARACTER ENCODING (not mandatory)
#-------------------------------------------------------------------------
export LANG="en_US.UTF-8"
export LC_COLLATE="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"
export LC_MESSAGES="en_US.UTF-8"
export LC_MONETARY="en_US.UTF-8"
export LC_NUMERIC="en_US.UTF-8"
export LC_TIME="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"


#-------------------------------------------------------------------------
# RUN RSTUDIO SERVER FROM SINGULARITY
#-------------------------------------------------------------------------
# This example bind mounts the /hpcnfs directory on the host into the Singularity container.
# By default the only host file systems mounted within the container are $HOME, /tmp, /proc, /sys, and /dev.
singularity exec --cleanenv \
   -H ${project_home} \
   --bind=${bind_path} \
   --bind="/home" \
   --bind="$TMPDIR/run:/run" \
   --bind="$TMPDIR/var-lib-rstudio-server:/var/lib/rstudio-server" \
   --bind="$TMPDIR/database.conf:/etc/rstudio/database.conf" \
   --bind="$TMPDIR/tmp:/tmp" \
   ${singularity_image} \
      rserver --www-port ${PORT} \
            --auth-none=0 \
            --auth-pam-helper-path=pam-helper \
            --auth-timeout-minutes=0 \
            --auth-stay-signed-in-days=30 \
            --server-user $SINGULARITYENV_USER

printf 'rserver exited' 1>&2
