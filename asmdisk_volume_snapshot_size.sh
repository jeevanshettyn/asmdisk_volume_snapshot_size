#!/bin/sh

#####################################################################################################################################
## SCRIPT NAME: asmdisk_volume_snapshot_size.sh                                                                                    ##
## PURPOSE    : To find the size of snapshot of ebs volumes, used as ASM disks                                                     ##
## USAGE      : asmdisk_volume_snapshot_size.sh                                                                                    ##
##                                                                                                                                 ##
## SCRIPT HISTORY:                                                                                                                 ##
## 06/02/2020  Jeevan Shetty        Initial Copy                                                                                   ##
##                                                                                                                                 ##
#####################################################################################################################################

SCRIPT=$0
v_region=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | rev | cut -c 2- | rev`
v_log='/tmp/disk_volume_mapping.log'
v_asm_disk_loc='/dev/oracleasm/disks'
v_aws_op_stg='/tmp/aws_op_stg.log'
v_snap_log='/tmp/aws_snap_change.log'

echo "`date` : Script - $SCRIPT Started" >$v_log

export ORACLE_SID="+ASM"
export ORAENV_ASK=NO
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin

. /usr/local/bin/oraenv >/dev/null

#
# Setting 64 bit libraries used by aws/python
#
export LD_LIBRARY_PATH=/usr/lib64:$LD_LIBRARY_PATH


#
# For every disk identified in above query, identify device name, EBS volume id and current disk size. These EBS volumes will be resized by increments defined in variable - v_vol_size_incr
#
ls $v_asm_disk_loc | grep -v "^ *$" | while read v_disk_name
do

    #
    # The major & minor# of asm disk under /dev/oracleasm/disks and disks under /dev/ match. This is used to identify the device name.
    # The device name will be used to identify the EBS volume id and current size, which will be eventually resized to v_new_vol_size.
    #
    v_major_minor_num=`ls -l $v_asm_disk_loc/$v_disk_name | tr -s ' ' | awk '{print $5,$6}'`

    #
    # Below we find the sub-partition name of the device, EBS volume id and its size
    #
    v_device=`ls -l /dev/nvme* | tr -s ' ' | grep -w "$v_major_minor_num" | cut -f 10 -d ' '`
    v_vol_id=`sudo nvme id-ctrl -v "$v_device" | grep "^sn" | cut -f 2 -d ':' | sed 's/ vol/vol-/'`
    v_vol_size=`aws ec2 describe-volumes --region $v_region --volume-id $v_vol_id --query "Volumes[0].{SIZE:Size}" | grep "SIZE" | tr -s ' ' | cut -f 3 -d ' '`

    echo "`date` : Below is the EBS Snapshot size for Disk = $v_disk_name, Device Name = $v_device, Volume = $v_vol_id, Current Size = $v_vol_size"

    aws ec2 describe-snapshots --filters Name=volume-id,Values="$v_vol_id" --query "Snapshots[*].{SnapshotId:SnapshotId,StartTime:StartTime}" | grep -E "SnapshotId|StartTime" | tr -s ' ' | sed 's/"//g; s/,//g' | tr -s ' ' | cut -f 3 -d  ' '  > $v_aws_op_stg
    v_cnt=`cat $v_aws_op_stg | wc -l`


    if [[ $v_cnt -gt 2 ]]
    then

        while read v_snap_id_1
        do
            read v_snap_time_1

            if [[ "$v_first_time" == "" ]]
            then
                v_snap_id_2=$v_snap_id_1
                v_snap_time_2=$v_snap_time_1

                read v_snap_id_1
                read v_snap_time_1

                v_first_time='NO'
            fi


            aws ebs list-changed-blocks --first-snapshot-id $v_snap_id_1 --second-snapshot-id $v_snap_id_2 > $v_snap_log
            v_blk_cnt=`grep "BlockIndex" $v_snap_log | wc -l`
            v_blk_size=`grep "BlockSize" $v_snap_log | tr -s ' ' | cut -f 3 -d ' ' | sed 's/,//g'`

            v_incr_size=`expr $v_blk_cnt \* $v_blk_size / 1024 / 1024`

            echo "`date` : Snap ID = $v_snap_id_2, Snap Time = $v_snap_time_2, Incr Size = $v_incr_size Mb"

            v_snap_id_2=$v_snap_id_1
            v_snap_time_2=$v_snap_time_1


        done < $v_aws_op_stg


        v_blk_cnt=`aws ebs list-snapshot-blocks --snapshot-id $v_snap_id_2 | grep "BlockIndex" | wc -l`
        v_incr_size=`expr $v_blk_cnt \* $v_blk_size / 1024 / 1024`

        echo "`date` : Oldest Snap ID = $v_snap_id_2, Snap Time = $v_snap_time_2, Oldest Snap Size = $v_incr_size Mb"

        v_first_time=""

        echo ""
    fi



done


echo "`date` : Script - $SCRIPT Completed" >>$v_log
echo "`date` : " >>$v_log
echo "`date` : " >>$v_log


