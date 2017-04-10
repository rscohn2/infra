#!/bin/bash

# This script installs all the compilers from s3 into a dir in /opt.
# On EC2 this location is on an EFS drive.

OPT=/opt/compiler-explorer
S3URL=s3://compiler-explorer/opt

set -ex
mkdir -p ${OPT}
cd ${OPT}

s3get() {
    aws s3 cp --force $*
}

fetch() {
    curl -v -L "$*"
}

do_unzip() {
    if [[ -z "$(which unzip 2>/dev/null)" ]]; then
        # Assume we're under alpine
        apk --update add unzip
    fi
    unzip "$*"
}

PATCHELF=${OPT}/patchelf-0.8/src/patchelf
if [[ ! -f $PATCHELF ]]; then
    if [[ -f /sbin/apk ]]; then
        # Assume we're under alpine
        apk --update add alpine-sdk
    fi
    fetch http://nixos.org/releases/patchelf/patchelf-0.8/patchelf-0.8.tar.gz | tar zxf -
    cd patchelf-0.8
    CFLAGS=-static LDFLAGS=-static CXXFLAGS=-static ./configure
    make -j$(nproc)
fi

do_strip() {
    find $1 -executable -type f | xargs strip || true
    find $1 -executable -type f | xargs --max-procs=$(nproc) -n 1 -I '{}' bash -c 'upx {} || true'
}

do_rust_install() {
    local DIR=$1
    local INSTALL=$2
    pushd /tmp
    fetch http://static.rust-lang.org/dist/${DIR}.tar.gz | tar zxvf -
    cd ${DIR}
    ./install.sh --prefix=${OPT}/${INSTALL} --verbose --without=rust-docs
    rm -rf /tmp/${DIR}
    popd
}

install_rust() {
    local NAME=$1

	if [[ -d rust-${NAME} ]]; then
        echo Skipping install of rust $NAME as already installed
		return
	fi
    echo Installing rust $NAME

    do_rust_install rustc-${NAME}-x86_64-unknown-linux-gnu rust-${NAME}
    
    # workaround for LD_LIBRARY_PATH
    ${PATCHELF} --set-rpath '$ORIGIN/../lib' ${OPT}/rust-${NAME}/bin/rustc
    for to_patch in ${OPT}/rust-${NAME}/lib/*.so; do
        ${PATCHELF} --set-rpath '$ORIGIN' $to_patch
    done
    
    # Don't need docs
    rm -rf ${OPT}/rust-${NAME}/share
    
    do_strip ${OPT}/rust-${NAME}
}

install_new_rust() {
    local NAME=$1
    local FORCE=$2
    local DIR=rust-${NAME}
    
    if [[ -n "$FORCE" && -d ${DIR} ]]; then
        local time_from=$(date -d "now - $FORCE" +%s)
        local dir_time=$(date -r ${DIR} +%s)
        if (( dir_time > time_from )); then
            echo "Treating ${DIR} as up to date enough, despite force"
            FORCE=""
        fi
    fi

    # force install if asked, or if there's no 'cargo' (which used to happen with older builds)
    if [[ -n "${FORCE}" || ! -x rust-${NAME}/bin/cargo ]]; then
        echo Forcing install of $NAME
        rm -rf rust-${NAME}
    fi

	if [[ -d rust-${NAME} ]]; then
        echo Skipping install of rust $NAME as already installed
		return
	fi
    echo Installing rust $NAME

    do_rust_install rust-${NAME}-x86_64-unknown-linux-gnu rust-${NAME}
    
    # workaround for LD_LIBRARY_PATH
    ${PATCHELF} --set-rpath '$ORIGIN/../lib' ${OPT}/rust-${NAME}/bin/rustc
    ${PATCHELF} --set-rpath '$ORIGIN/../lib' ${OPT}/rust-${NAME}/bin/cargo
    for to_patch in ${OPT}/rust-${NAME}/lib/*.so; do
        ${PATCHELF} --set-rpath '$ORIGIN' $to_patch
    done
    
    # Don't need docs
    rm -rf ${OPT}/rust-${NAME}/share

    do_strip ${OPT}/rust-${NAME}
}

#########################
# RUST
install_new_rust nightly '1 day'
install_new_rust beta '1 week'
install_new_rust 1.5.0
install_new_rust 1.6.0
install_new_rust 1.7.0
install_new_rust 1.8.0
install_new_rust 1.9.0
install_new_rust 1.10.0
install_new_rust 1.11.0
install_new_rust 1.12.0
install_new_rust 1.13.0
install_new_rust 1.14.0
install_new_rust 1.15.1
install_new_rust 1.16.0

install_rust 1.0.0
install_rust 1.1.0
install_rust 1.2.0
install_rust 1.3.0
install_rust 1.4.0
#########################

#########################
# GO
if [[ ! -d ${OPT}/go ]]; then
    fetch https://storage.googleapis.com/golang/go1.4.1.linux-amd64.tar.gz | tar zxf -
    do_strip ${OPT}/go
fi
#########################


#########################
# D

getgdc() {
    vers=$1
    build=$2
    if [[ -d gdc${vers} ]]; then
        echo D ${vers} already installed, skipping
        return
    fi
    mkdir gdc${vers}
    pushd gdc${vers}
    fetch ftp://ftp.gdcproject.org/binaries/${vers}/x86_64-linux-gnu/gdc-${vers}+${build}.tar.xz | tar Jxf -
    # stripping the D libraries seems to upset them, so just strip the exes
    do_strip x86_64-pc-linux-gnu/bin
    do_strip x86_64-pc-linux-gnu/libexec
    popd
}

getldc() {
    vers=$1
    if [[ -d ldc${vers} ]]; then
        echo LDC ${vers} already installed, skipping
        return
    fi
    mkdir ldc${vers}
    pushd ldc${vers}
    fetch https://github.com/ldc-developers/ldc/releases/download/v${vers}/ldc2-${vers}-linux-x86_64.tar.xz | tar Jxf -    
    # any kind of stripping upsets ldc
    popd
}

getldc_latestbeta() {
    vers=$(curl https://ldc-developers.github.io/LATEST_BETA)
    if [[ ! -d ldcbeta ]]; then
        mkdir ldcbeta
    fi
    pushd ldcbeta
    if [[ "$(cat .version)" = "${vers}" ]]; then
        echo "LDC beta version ${vers} already installed, skipping"
        popd
        return
    fi
    rm -rf *
    fetch https://github.com/ldc-developers/ldc/releases/download/v${vers}/ldc2-${vers}-linux-x86_64.tar.xz | tar Jxf - --strip-components 1
    echo "${vers}" > .version
    # any kind of stripping upsets ldc
    popd
}

getgdc 4.8.2 2.064.2
getgdc 4.9.3 2.066.1
getgdc 5.2.0 2.066.1
getldc 0.17.2
getldc 1.0.0
getldc 1.1.0
getldc_latestbeta
#########################

#########################
# C++
# 12.04 compilers (mostly)
for compiler in clang-3.2.tar.gz \
    clang-3.3.tar.gz \
    intel.tar.gz
do
    DIR=${compiler%.tar.*}
	if [[ ! -d ${DIR} ]]; then
		s3get ${S3URL}/$compiler ${OPT}/$compiler
		tar zxf $compiler
		rm $compiler
		do_strip ${DIR}
	fi
done
# Workaround for Intel license
mkdir -p ${OPT}/composer_xe_2013.1.117/Licenses/
cp ${OPT}/intel/licenses/* ${OPT}/composer_xe_2013.1.117/Licenses/

# clangs
for clang in \
    3.0-x86_64-linux-Ubuntu-11_10 \
    3.1-x86_64-linux-ubuntu_12.04 \
; do
    DIR=clang+llvm-${clang}
    VERSION=$(echo ${clang} | grep -oE '^[0-9.]+')
    if [[ ! -d ${DIR} ]]; then
        fetch http://llvm.org/releases/${VERSION}/clang+llvm-${clang}.tar.gz | tar zxf -
        do_strip ${DIR}
    fi
done
for clang in \
    3.4.1-x86_64-unknown-ubuntu12.04 \
    3.5.0-x86_64-linux-gnu-ubuntu-14.04 \
    3.5.1-x86_64-linux-gnu \
    3.5.1-x86_64-linux-gnu \
    3.5.2-x86_64-linux-gnu-ubuntu-14.04 \
    3.6.2-x86_64-linux-gnu-ubuntu-14.04 \
    3.7.0-x86_64-linux-gnu-ubuntu-14.04 \
    3.7.1-x86_64-linux-gnu-ubuntu-14.04 \
    3.8.0-x86_64-linux-gnu-ubuntu-14.04 \
    3.8.1-x86_64-linux-gnu-ubuntu-14.04 \
    3.9.0-x86_64-linux-gnu-ubuntu-16.04 \
; do
    DIR=clang+llvm-${clang}
    VERSION=$(echo ${clang} | grep -oE '^[0-9.]+')
    # stupid naming issues on clang
    if [[ "${VERSION}" = "3.5.0" ]]; then
        DIR=clang+llvm-3.5.0-x86_64-linux-gnu
    fi
    if [[ "${VERSION}" = "3.5.2" ]]; then
        DIR=clang+llvm-3.5.2-x86_64-linux-gnu
    fi
    if [[ ! -d ${DIR} ]]; then
        fetch http://llvm.org/releases/${VERSION}/clang+llvm-${clang}.tar.xz | tar Jxf -
        do_strip ${DIR}
    fi
done

# ellccs
for VERSION in 0.1.33 \
               0.1.34 \
; do
    DIR=ellcc-${VERSION}
    if [[ -d ${DIR} ]]; then
        echo ${DIR} installed already
    else
        fetch http://ellcc.org/releases/ellcc-x86_64-linux-${VERSION}.tgz  | tar xzf -
        mv ellcc ${DIR}
        do_strip ${DIR}
    fi
done


# Custom-built GCCs are already UPX's and stripped
# (notes on various compiler builds below:
# 4.7.0 fails to build with a libgcc compile error:
#   ./md-unwind-support.h:144:17: error: field 'info' has incomplete type
# )
for version in \
    4.6.4 \
    4.7.{1,2,3,4} \
    4.8.{1,2,3,4,5} \
    4.9.{0,1,2,3,4} \
    5.{1,2,3,4}.0 \
    6.{1,2,3}.0 \
; do
    if [[ ! -d gcc-${version} ]]; then
        compiler=gcc-${version}.tar.xz
        s3get ${S3URL}/$compiler ${OPT}/$compiler
        tar axf $compiler
        rm $compiler
    fi
done

# other architectures
gcc_arch_install() {
    local arch=$1
    local version=$2
    local xz=${arch}-gcc-${version}.tar.xz
    local dir=${arch}/gcc-${version}
    mkdir -p ${arch}
    if [[ ! -d ${dir} ]]; then
        s3get ${S3URL}/${xz} ${OPT}/${xz}
        tar axf ${OPT}/${xz} -C ${OPT}/${arch}
        rm ${xz}
    fi
}
gcc_arch_install arm 4.5.4
gcc_arch_install arm 4.6.4
gcc_arch_install avr 4.5.4
gcc_arch_install avr 4.6.4
gcc_arch_install msp430 4.5.3

# snapshots/trunk
compilers=$(aws s3 ls ${S3URL}/ | grep -oE 'gcc-(7|trunk)-[0-9]+' | sort)
compiler_array=(${compilers})
latest=${compiler_array[-1]}
# Extract the latest...
if [[ ! -d ${latest} ]]; then
    s3get ${S3URL}/${latest}.tar.xz ${OPT}/$latest.tar.xz
    tar axf $latest.tar.xz
    rm $latest.tar.xz
fi
# Ensure the symlink points at the latest
rm -f ${OPT}/gcc-7-snapshot
ln -s ${latest} ${OPT}/gcc-7-snapshot
# Clean up any old snapshots
for compiler in gcc-{7,trunk}-[0-9]*; do
    if [[ -d ${compiler} ]]; then
        if [[ "${compiler}" != "${latest}" ]]; then
            rm -rf ${compiler}
        fi
    fi
done

# Custom-built clangs also stripped and UPX'd
for version in \
    3.9.1 \
    4.0.0 \
; do
    if [[ ! -d clang-${version} ]]; then
        compiler=clang-${version}.tar.xz
        s3get ${S3URL}/$compiler ${OPT}/$compiler
        tar axf $compiler
        rm $compiler
    fi
done

# trunk builds
compilers=$(aws s3 ls ${S3URL}/ | grep -oE "clang-trunk-[0-9]+" | sort)
compiler_array=(${compilers})
latest=${compiler_array[-1]}
# Extract the latest...
if [[ ! -d ${latest} ]]; then
    s3get ${S3URL}/${latest}.tar.xz ${OPT}/$latest.tar.xz
    tar axf $latest.tar.xz
    rm $latest.tar.xz
fi
# Ensure the symlink points at the latest
rm -f ${OPT}/clang-trunk
ln -s ${latest} ${OPT}/clang-trunk
# Clean up any old snapshots
for compiler in clang-trunk-[0-9]*; do
    if [[ -d ${compiler} ]]; then
        if [[ "${compiler}" != "${latest}" ]]; then
            rm -rf ${compiler}
        fi
    fi
done

# ICCs also UPX'd
for version in 2016.3.210; do
    if [[ ! -d intel-${version} ]]; then
        compiler=intel-${version}.tar.xz
        s3get ${S3URL}/$compiler ${OPT}/$compiler
        tar axf $compiler
        rm $compiler
    fi
done

# Oracle dev studio is stored on s3 only as it's behind a login screen on the
# oracle site. It doesn't like being strip()ped
for version in 12.5; do
    fullname=OracleDeveloperStudio${version}-linux-x86-bin
    if [[ ! -d ${fullname} ]]; then
        compiler=${fullname}.tar.bz2
        s3get ${S3URL}/$compiler ${OPT}/$compiler
        tar axf $compiler
        rm $compiler
    fi
done

# Zapcc
for version in 20170226-190308-1.0; do
    fullname=zapcc-${version}
    if [[ ! -d ${fullname} ]]; then
        compiler=${fullname}.tar.gz
        s3get ${S3URL}/${compiler} ${OPT}/$compiler
        tar axf $compiler
        rm $compiler
        s3get ${S3URL}/zapcc-key.txt ${OPT}/${fullname}/bin/zapcc-key.txt
    fi
done

# MSP compilers
if [[ ! -d msp430-gcc-5.3.0.219_linux32 ]]; then
    fetch http://software-dl.ti.com/msp430/msp430_public_sw/mcu/msp430/MSPGCC/latest/exports/msp430-gcc-4.1.0.0_linux32.tar.bz2 | tar jxf -
    do_strip msp430-gcc-5.3.0.219_linux32
fi
if [[ ! -d msp430-gcc-6.2.1.16_linux64 ]]; then
    fetch http://software-dl.ti.com/msp430/msp430_public_sw/mcu/msp430/MSPGCC/latest/exports/msp430-gcc-6.2.1.16_linux64.tar.bz2 | tar jxf -
    do_strip msp430-gcc-6.2.1.16_linux64
fi

# GNU ARM Embedded toolchain
if [[ ! -d gcc-arm-none-eabi-5_4-2016q3 ]]; then
    fetch https://launchpad.net/gcc-arm-embedded/5.0/5-2016-q3-update/+download/gcc-arm-none-eabi-5_4-2016q3-20160926-linux.tar.bz2 | tar jxf -
    do_strip gcc-arm-none-eabi-5_4-2016q3 
fi

# Windows compilers
fix_up_windows() {
    local file=$1
    if [[ -d ${file}/lib/native/bin/amd64 ]]; then
        cp ${file}/lib/native/bin/amd64/mspdb140.dll ${file}/lib/native/bin/amd64_arm/
        cp ${file}/lib/native/bin/amd64/msvcdis140.dll ${file}/lib/native/bin/amd64_arm/
        cp ${file}/lib/native/bin/amd64/mspdb140.dll ${file}/lib/native/bin/amd64_x86/
    fi
}

mkdir -p windows
pushd windows
for file in \
    10.0.10240.0 \
    14.0.24224-Pre \
    19.10.25017 \
; do
    if [[ ! -d ${file} ]]; then
        s3get ${S3URL}/${file}.tar.xz ${file}.tar.xz
        tar Jxf ${file}.tar.xz
        fix_up_windows ${file}
        rm ${file}.tar.xz
    fi
done

for file in \
    14.0.24629 \
; do
    if [[ ! -d ${file} ]]; then
        mkdir ${file}
        pushd ${file}
        fetch http://vcppdogfooding.azurewebsites.net/api/v2/package/visualcpptools/${file} > ${file}.zip
        do_unzip ${file}.zip
        rm ${file}.zip
        popd
        fix_up_windows ${file}
    fi
done
popd
#########################


#########################
# node.js

TARGET_NODE_VERSION=v6.10.0
CURRENT_NODE_VERSION=""
if [[ -d node ]]; then
    CURRENT_NODE_VERSION=$(node/bin/node --version)
fi

if [[ "$TARGET_NODE_VERSION" != "$CURRENT_NODE_VERSION" ]]; then
    echo "Installing node $CURRENT_NODE_VERSION"
    rm -rf node
    fetch "https://nodejs.org/dist/${TARGET_NODE_VERSION}/node-${TARGET_NODE_VERSION}-linux-x64.tar.gz" | tar zxf - && mv node-${TARGET_NODE_VERSION}-linux-x64 node
fi