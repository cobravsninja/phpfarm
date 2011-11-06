#!/bin/bash
#
# phpfarm
#
# Installs multiple versions of PHP beside each other.
# Both CLI and CGI versions are compiled.
# Sources are fetched from museum.php.net if no
# corresponding file bzips/php-$version.tar.bz2 exists.
#
# Usage:
# ./compile.sh 5.3.1
#
# You should add ../inst/bin to your $PATH to have easy access
# to all php binaries. The executables are called
# php-$version and php-cgi-$version
#
# In case the options in options.sh do not suit you or you just need
# different options for different php versions, you may create
# custom/options-$version.sh scripts that define a $configoptions
# variable. See options.sh for more details.
#
# Put pyrus.phar into bzips/ to automatically get version-specific
# pyrus/pear2 commands.
#
# Author: Christian Weiske <cweiske@php.net>
#

version=$1
vmajor=`echo ${version%%.*}`
vminor=`echo ${version%.*}`
vminor=`echo ${vminor#*.}`
vpatch=`echo ${version##*.}`

#directory of this file. all php sources are extracted in it
basedir="`dirname "$0"`"
cd "$basedir"
basedir=`pwd`
#directory of php sources of specific version
srcdir="php-$version"
#directory with source archives
bzipsdir='bzips'
#directory phps get installed into
instbasedir="`readlink -f "$basedir/../inst"`"
#directory this specific version gets installed into
instdir="$instbasedir/php-$version"
#directory where all bins are symlinked
shbindir="$instbasedir/bin"

#we need a php version
if [ "x$version" = 'x' ]; then
    echo 'Please specify php version'
    exit 1
fi

#already extracted?
if [ ! -d "$srcdir" ]; then
    echo 'Source directory does not exist; trying to extract'
    srcfile="$bzipsdir/php-$version.tar.bz2"
    if [ ! -e "$srcfile" ]; then
        echo 'Source file not found:'
        echo "$srcfile"
        url="http://museum.php.net/php$vmajor/php-$version.tar.bz2"
        wget -P "$bzipsdir" "$url"
        if [ ! -f "$srcfile" ]; then
            echo "Fetching sources from museum failed"
            echo $url
            #museum failed, now we try real download
            url="http://www.php.net/get/php-$version.tar.bz2/from/this/mirror"
            wget -P "$bzipsdir" -O "$srcfile" "$url"
        fi
        if [ ! -s "$srcfile" -a -f "$srcfile" ]; then
            rm "$srcfile"
        fi

        if [ ! -f "$srcfile" ]; then
            echo "Fetching sources from official download site failed"
            echo $url
            #use ilia's RC (5.3.x)
            url="https://downloads.php.net/ilia/php-$version.tar.bz2"
            wget -P "$bzipsdir" -O "$srcfile" "$url"
        fi
        if [ ! -s "$srcfile" -a -f "$srcfile" ]; then
            rm "$srcfile"
        fi

        if [ ! -f "$srcfile" ]; then
            echo "Fetching sources from ilia's site failed"
            echo $url
            #use stas's RC (5.4.x)
            url="https://downloads.php.net/stas/php-$version.tar.bz2"
            wget -P "$bzipsdir" -O "$srcfile" "$url"
        fi
        if [ ! -s "$srcfile" -a -f "$srcfile" ]; then
            rm "$srcfile"
        fi

        if [ ! -f "$srcfile" ]; then
            echo "Fetching sources failed:"
            echo $url
            exit 2
        fi
    fi
    #extract
    tar xjvf "$srcfile"
fi

#read customizations
source 'options.sh' "$version" "$vmajor" "$vminor" "$vpatch"
cd "$srcdir"

#only configure/make during the first install of a new version
#or after some change occurred in customizations.
tstamp=0
if [ -f "config.nice" ]; then
   tstamp=`stat -c '%Y' "config.nice"`
fi

if [ $configure -gt $tstamp ]; then
    #configuring
    echo "(Re-)configuring"
    ./configure \
     $configoptions \
     --prefix="$instdir" \
     --exec-prefix="$instdir" \
     --with-pear="$instdir/pear"

    if [ $? -gt 0 ]; then
        echo configure.sh failed.
        exit 3
    fi
fi


# Check that no unknown options have been used.
unknown_options=
if [ -e "config.status" ]; then
    unknown_options=`sed -ne '/Following unknown configure options were used/,/for available options/p' config.status | sed -n -e '$d' -e '/^$/d' -e '3,$p'`
fi
# PHP 5.4 uses a different way to report such problems.
if [ -z "$unknown_options" -a -e "config.log" ]; then
    unknown_options=`sed -n -r -e 's/configure:[^\020]+WARNING: unrecognized options: //p' config.log`
fi

if [ -n "$unknown_options" ]; then
    # If the error comes from a previous run, ./configure won't kick in and
    # it won't display the error message. We do the work in its place here.
    if [ $configure -le $tstamp ]; then
        echo "ERROR: The following unrecognized configure options were used:"
        echo ""
        echo $unknown_options
        echo ""
        echo "Check 'configure --help' for available options."
    fi
    echo "Please fix your configure options and try again."
    exit 3
fi

if [ $configure -gt $tstamp -o ! -f sapi/cli/php ]; then
    #compile sources
    #make clean
    make
    if [ "$?" -gt 0 ]; then
        echo make failed.
        exit 4
    fi
fi

make install
if [ "$?" -gt 0 ]; then
    echo make install failed.
    exit 5
fi

#copy php.ini
initarget="$instdir/etc/php.ini"
if [ -f "php.ini-development" ]; then
    #php 5.3
    cp "php.ini-development" "$initarget"
elif [ -f "php.ini-recommended" ]; then
    #php 5.1, 5.2
    cp "php.ini-recommended" "$initarget"
else
    echo "No php.ini file found."
    echo "Please copy it manually to $instdir/etc/php.ini"
fi

#set default ini values
cd "$basedir"
if [ -f "$initarget" ]; then
    #fixme: make the options unique or so
    custom="custom/php.ini"
    [ ! -e "$custom" ] && cp "default-custom-php.ini" "$custom"

    ext_dir=`"$instdir/bin/php-config" --extension-dir`
    for suffix in "" "-$vmajor" "-$vmajor.$vminor" "-$vmajor.$vminor.$vpatch"; do
        custom="custom/php$suffix.ini"
        [ -e "$custom" ] && sed -e 's#$ext_dir#'"$ext_dir"'#' "$custom" >> "$initarget"
    done
fi

#create bin
[ ! -d "$shbindir" ] && mkdir "$shbindir"
if [ ! -d "$shbindir" ]; then
    echo "Cannot create shared bin dir"
    exit 6
fi
#symlink all files

#php may be called php.gcno
bphp="$instdir/bin/php"
bphpgcno="$instdir/bin/php.gcno"
if [ -f "$bphp" ]; then
    ln -fs "$bphp" "$shbindir/php-$version"
elif [ -f "$bphpgcno" ]; then
    ln -fs "$bphpgcno" "$shbindir/php-$version"
else
    echo "no php binary found"
    exit 7
fi

#php-cgi may be called php.gcno
bphpcgi="$instdir/bin/php-cgi"
bphpcgigcno="$instdir/bin/php-cgi.gcno"
if [ -f "$bphpcgi" ]; then
    ln -fs "$bphpcgi" "$shbindir/php-cgi-$version"
elif [ -f "$bphpcgigcno" ]; then
    ln -fs "$bphpcgigcno" "$shbindir/php-cgi-$version"
else
    echo "no php-cgi binary found"
    exit 8
fi

ln -fs "$instdir/bin/php-config" "$shbindir/php-config-$version"
ln -fs "$instdir/bin/phpize" "$shbindir/phpize-$version"

# If PEAR was installed, finish the setup here.
if [ -e "$instdir/bin/pear" ]; then
    ln -fs "$instdir/bin/pear" "$shbindir/pear-$version"
    ln -fs "$instdir/bin/peardev" "$shbindir/peardev-$version"
    ln -fs "$instdir/bin/pecl" "$shbindir/pecl-$version"
fi

# Recent versions of PHP come with a phar.phar archive
# that makes it easy to manipulate PHP archives.
# Let's be user-friendly and add a link to it if it exists.
if [ -e "$instdir/bin/phar.phar" ]; then
    ln -fs "$instdir/bin/phar.phar" "$shbindir/phar-$version"
fi

# Use as main version if necessary.
if [ "$version" = "$PHPFARM_MAIN_VERSION" ]; then
    for prog in php php-cgi php-config phpize pear peardev pecl phar; do
        if [ -e "$shbindir/${prog}-$version" ]; then
            echo "Marking ${prog}-$version as the main version of $prog."
            ln -fs "$shbindir/${prog}-$version" "$shbindir/$prog"
        fi
    done
fi

cd "$basedir"
./pyrus.sh "$version" "$instdir"

# Post-install stuff
for suffix in "" "-$vmajor" "-$vmajor.$vminor" "-$vmajor.$vminor.$vpatch"; do
    post="custom/post-install$suffix.sh"
    [ -e "$post" ] && /bin/bash "$post" "$version" "$instdir" "$shbindir"
done
exit 0
