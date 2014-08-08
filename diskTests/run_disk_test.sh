#!/bin/bash

#DEFAULT VALUES
OUTPUT="fio"
DATADIR="/tmp/"
LOOPS=1
PLOT='n'

_FIO_IO_PATTERN="write"
_FIO_IO_SIZE="8m"
_FIO_BLOCK_SIZE="128 256 512 1k"
_FIO_IO_TYPE="fsync"
_FIO_IO_ENGINE="sync"

function usage()
{
    echo
    echo "Usage: `basename $0` [-o OUTPUT] [-d DATADIR] [-l LOOPS] [-h]"
    echo
    echo -e "    -o OUTPUT: Output directory to put the results, fio by default"
    echo -e "    -d DATADIR: Directory to put the data. /tmp/ by default."
    echo -e "    -l LOOPS: Run for loops."
    echo -p "    -p PLOT: Plot graphes"
    echo -e "    -h Show usage."
    echo
}

while getopts "ho:d:l:p" opt; do
    case $opt in
        "h")
            usage
            exit 0
            ;;
        "d")
            DATADIR="$OPTARG"
            ;;
        "o")
            OUTPUT="$OPTARG"
            ;;
        "l")
            LOOPS="$OPTARG"
            ;;
        "p")
            PLOT='y'
            ;;
        *)
            usage
            exit 1
        ;;
    esac
done
shift $(($OPTIND-1))

workdir=`cd $(dirname ${BASH_SOURCE[0]}); pwd | xargs readlink -f`



function run_test()
{
  loop_num=$1
  tcdir=${workdir}/${OUTPUT}_${loop_num}
  rsdir=${workdir}/${OUTPUT}_${loop_num}
  logdir=${workdir}/${OUTPUT}_${loop_num}/logs
  plotdir=${workdir}/${OUTPUT}_${loop_num}/plots

  time=`date +%Y%m%d%H%M%S`

  DATADIR_SUB=`echo ${DATADIR} | sed "s/\//\_/g"`
  DATADIR_SUB=${DATADIR_SUB%_}

  #clean dirs
  [ -d ${tcdir} ] && rm -rf ${tcdir}/*
  [ -d ${rsdir} ] && rm -rf ${rsdir}/*
  [ -d ${plotdir} ] && rm -rf ${plotdir}/*
  [ -d ${logdir} ] && rm -rf ${logdir}/*
  [ -d ${DATADIR} ] && rm -f ${DATADIR}/FIO*.io
  mkdir -p ${tcdir} ${rsdir} ${plotdir} ${logdir}

  #create testcases
  cat > ${tcdir}/full_disk_test.fio <<EOF
[global]
size=8m
overwrite=0
file_append=1
loops=2
iodepth=1
rw=write
thinktime=10
thinktime_spin=6
ioengine=sync
sync=1
runtime=10s

EOF
  for fsize in ${_FIO_BLOCK_SIZE}; do
    cat >> ${tcdir}/full_disk_test.fio <<EOF
[FIO_${fsize}_new${DATADIR_SUB}]
directory=${DATADIR}
bs=${fsize}
write_lat_log=FIO_${fsize}_new${DATADIR_SUB}
filename=FIO_${fsize}_${DATADIR_SUB}.io
stonewall

EOF
    cat >> ${tcdir}/full_disk_test.fio <<EOF
[FIO_${fsize}_append${DATADIR_SUB}]
directory=${DATADIR}
bs=${fsize}
write_lat_log=FIO_${fsize}_append${DATADIR_SUB}
filename=FIO_${fsize}_${DATADIR_SUB}.io
stonewall

EOF
  done

  #run testcase
  fio --output-format=terse --output ${rsdir}/full_disk_terse.result ${tcdir}/full_disk_test.fio
  mv FIO*.log ${logdir}
  cd ${logdir}
  if [ ${PLOT} = 'y' ]; then
    fio2gnuplot -p 'FIO*_lat.log' -d ${plotdir} -t lattency_in_us -g
  fi
  cd ${workdir}

  # parse output

  awk -F';' 'BEGIN {printf("%s %22s %8s %8s %8s\n", "jobname", "avg_lat(us)","min_lat(us)","max_lat(us)","std_dev")} $1 == 3 \
    { printf("%-23s %6.2f %11.2f %11.2f %8.2f\n", $3, $57,$55,$56,$58)}' ${rsdir}/full_disk_terse.result > ${rsdir}/lat.result

  cat ${rsdir}/lat.result
}


number=0
while [ ${number} -lt ${LOOPS} ]; do
    run_test ${number}
    number=$((number+1))
done

