#! /usr/bin/env /bin/bash

show_help() {
  cat <<EOF

  Name:
    make-alternatives-for-java.

  Synopsis:
    make-alternatives-for-java.sh
            [-i] [-s] [-a] [-r] [-p n] [-t target] [-d] [-h] java-home-path

  Description:
        make-alternatives-for-java.sh: a wrapper for update-alternatives that
        creates and removes the symbolic links comprising the Debian alternatives
        for executables associated with with a Java JDK.

    -i  install alternatives for executables located at
        java-home-path/jre/bin and java-home-directory/bin. Those in
        jre/bin take precedence over those with the same name as those in
        java-home-path/bin.

    -s  switch alternatives for executables to the JDK at
        java-home-path from the current active alternative.

    -a  switch alternatives for executables for the JDK at
        java-home-path to auto mode.

    -r  remove all the alternatives that were installed from java-home-path.

    -p n
        priority.  See man page for update-alternatives.

    -t directory
        the name of the directory where the master link is to be installed.
        Default: /usr/local/bin

    -n  Perform a "dry run" by echoing the commands that would be performed.

    -h  Show this text.

    java-home-path

  Directories of interest that concern update-alternatives:
    /etc/alternatives /var/lib/dkpg/var/lib/dpkg/alternatives
EOF
}

show_warning() {
  cat <<EOF
    *** WARNING ***
      Alternatives for JREs/JDKs may contain executables that may exist in
      one and not the other alternative, i.e., JRE/JDK 1.8 vs 11.0.

EOF
}

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize our variables:
install=0
switchalt=0
auto=0
priority=20
remove=0
dryrun=0
target_root=/usr/local

while getopts "hisarnlp:t:" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    i)  install=1
        action="--install"
        show_warning
        ;;
    s)  switchalt=1
        action="--force --set"
        show_warning
        ;;
    a)  auto=1
        action="--auto"
        ;;
    r)  remove=1
        action="--remove"
        ;;
    p)	priority=$OPTARG
      	if ! [[ $priority =~ ^[0-9]+$ ]]; then
      		echo "Invalid -p $priority: argument not a number."
      		exit 1
        fi
      	;;
    t)  target_root=$OPTARG
        ;;
    n)	dryrun=1
    	;;
    esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift

if [[ $(( install + remove )) -eq 2 ]]; then
  echo 'Flags "-i" and "-r" cannot be both set.'
  exit 1
fi
[[ $(( install + remove + switchalt + auto )) -eq 0 ]] || [ $dryrun -eq 1 ] \
&& dryrun=1; action=${action:-dry-run}

: ${JAVA_HOME_ROOT=${1:-xxx}}

if [ ! -e "$JAVA_HOME_ROOT/jre/bin/java" \
-a ! -e "$JAVA_HOME_ROOT/bin/java" ]; then
	echo "$JAVA_HOME_ROOT is not a valid JRE/JDK home directory."
	exit 1
fi

# Location of alternatives config files: /var/lib/dpkg/alternatives/

# Example:
# update-alternatives --install /usr/local/bin/java java /opt/java/jdk11.0/bin/java 20
# update-alternatives --install /usr/local/bin/java java /opt/java/jdk11.0/bin/java 20
#  --slave /usr/local/man/man1/java.1 java.1 /opt/java/jdk11.0/man/man1/java.1

# Those exes not bin
JEXTRAS=($JAVA_HOME_ROOT/jre/lib/jexec $JAVA_HOME_ROOT/lib/jexec)

linkman=$target_root/man/man1
pathman=$JAVA_HOME_ROOT/man/man1

if [ ! -e "$pathman" ]; then
	[ $dryrun -ne 0 ] && echo "Making man1 directory $pathman ..."; mkdir -p "$pathman"
fi

base_cmd="update-alternatives $action"

# Fill array with exes from jre/bin if any.
[ -e "$JAVA_HOME_ROOT/jre/bin" ] && jrebin=$(ls $JAVA_HOME_ROOT/jre/bin/*)
if [ -e "$JAVA_HOME_ROOT/jre/lib" ]; then
  jrelib=$(printf '%s\n' ${JEXTRAS[@]} | egrep "jre/lib")
  jrebin=(${jrebin[@]} ${jrelib[@]})
fi

# Install
if [ $install -eq 1 ]; then
	echo "Installing java alternatives for $JAVA_HOME_ROOT"

	for pathexe in $JAVA_HOME_ROOT/jre/bin/* $JAVA_HOME_ROOT/bin/* ${JEXTRAS[@]}
	do
		if [ -x "$pathexe" ]; then

			# Exclude .cgi and .ini stuff.
			[[ $pathexe =~ \.cgi$ ]] || [[ $pathexe =~ \.ini$ ]] && continue

  		name=$(basename $pathexe)
			linkbin=$target_root/bin/$name

			if [[ $pathexe =~ ${JAVA_HOME_ROOT}/(bin|lib) ]]; then
				# Do not install from jdk bin if already in jre/bin.
				if printf '%s\n' ${jrebin[@]} | egrep -q "${name}$"; then
					echo "$name found in jre/bin skiping ..."
					continue
				fi
			fi

			if [ -e "$pathman" ]; then
				if [ -e "$pathman/$name.1" ]; then
					 man1name=$name.1
				elif [ -e "$pathman/$name.1.gz" ]; then
					man1name=$pathman/$name.1.gz
				else
					man1name=xxx
				fi
			fi

			cmd="$base_cmd $linkbin $name $pathexe $priority"
			[ "$man1name" != 'xxx' ] && cmd="$cmd --slave $linkman/$man1name $man1name $pathman/$man1name"
			if [ $dryrun -eq 1 ]; then
        echo "$cmd"
      else
        $cmd
      fi
		fi
	done
  exit 0
fi

# Remove by group or set group to auto
if [ $remove -eq 1 -o $auto -eq 1 ]; then
  if [ $auto -eq 1 ]; then
    echo "Switchingjava alternatives for $JAVA_HOME_ROOT to auto mode"
  else
  	echo "Removing java alternatives for $JAVA_HOME_ROOT"
  fi

	for pathexe in $JAVA_HOME_ROOT/jre/bin/* $JAVA_HOME_ROOT/bin/* ${JEXTRAS[@]}
	do
		if [ -x "$pathexe" ]; then

			# Exclude .cgi and .ini stuff.
			[[ $pathexe =~ \.cgi$ ]] || [[ $pathexe =~ \.ini$ ]] && continue

			name=$(basename $pathexe)

      if [ $auto -eq 1 ]; then
        cmd="$base_cmd $name"
      else
  			cmd="$base_cmd $name $pathexe"
      fi
			if [ $dryrun -eq 1 ]; then
        echo "# $cmd"
      else
        $cmd
      fi
		fi
	done
  exit 0
fi

# Swtich to another alternative.
if [ $switchalt -eq 1 ]; then
	echo "Switching java alternatives to $JAVA_HOME_ROOT"

	for pathexe in $JAVA_HOME_ROOT/jre/bin/* $JAVA_HOME_ROOT/bin/* ${JEXTRAS[@]}
	do
		if [ -x "$pathexe" ]; then

			# Exclude .cgi and .ini stuff.
			[[ $pathexe =~ \.cgi$ ]] || [[ $pathexe =~ \.ini$ ]] && continue

			name=$(basename $pathexe)
      docmd="update-alternatives --get-selections | egrep '^$name\s+' | awk '{ print \$3; }'"
      curalt=$(eval $docmd)
      # Nothing to do if they match.
      [[ $curalt =~ $pathexe ]] && continue

			if [[ $pathexe =~ ${JAVA_HOME_ROOT}/(bin|lib) ]]; then
				# Do not switch if already in jre/(bi|lib).
				if printf '%s\n' ${jrebin[@]} | egrep -q "${name}$"; then
					# echo "$name found in jre/(bin|lib)  ..."
          # pathexe="$JAVA_HOME_ROOT/jre/$BASH_REMATCH[1]/$name"
          echo "Skipping $pathexe already in jre/bin ..."
          continue
				fi
      fi

			cmd="$base_cmd $name $pathexe"
			if [ $dryrun -eq 1 ]; then
        echo "# $curalt -> $cmd"
      else
        $cmd
      fi
		fi
	done
  exit 0
fi

[[ $(( install + remove + switchalt )) -eq 0 ]] && echo "There is nothing to do!!!"
