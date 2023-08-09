#!/bin/bash

set -ue

SLIDE_SVG_LIST=$*
NUM_SLIDES=$(printf "%s\n" $SLIDE_SVG_LIST | wc -l)
RESULT_SIMH=result.simh
START_ADDR='100'

add_addr() {
	local addr=$1
	local val=$2
	bc <<< "obase=8;ibase=8;$addr + $val"
}

inc_saddr() {
	START_ADDR=$(add_addr $START_ADDR 1)
}

# 全スライドについてのType 340命令列を出力
TY340_START_ADDR_LIST=''
for svg_file in $SLIDE_SVG_LIST; do
	name=$(echo $svg_file | rev | cut -d'.' -f2- | rev)
	if [ ! -f ${name}.csv ]; then
		tools/svg2ld $svg_file ${name}.csv
	fi
	if [ ! -f ${name}.340ml ]; then
		tools/ld2ml ${name}.csv ${name}.340ml
	fi
	if [ ! -f ${name}.340simh ]; then
		tools/ml2simh ${name}.340ml ${name}.340simh $START_ADDR
	fi
	cat ${name}.340simh
	TY340_START_ADDR_LIST="$TY340_START_ADDR_LIST $START_ADDR"
	START_ADDR=$(tail -n 1 ${name}.340simh | cut -d' ' -f2)
	inc_saddr
done >${RESULT_SIMH}

# スライドショーのためのPDP-7命令列を出力
PROG_START_ADDR=$START_ADDR
current_slide_idx=0
for ty340_saddr in $TY340_START_ADDR_LIST; do
	slide_prog_saddr=$START_ADDR
	sed -i "s/__NEXT_SLIDE_PROG_ADDR__/$slide_prog_saddr/" ${RESULT_SIMH}

	{
		echo "d -m $START_ADDR law $ty340_saddr"; inc_saddr
		echo "d -m $START_ADDR idla"; inc_saddr
		draw_loop_saddr=$START_ADDR

		# TTY⽂字⼊⼒に応じた処理
		## 文字⼊⼒フラグがセットされているか？
		echo "d -m $START_ADDR ksf"; inc_saddr
		## 現在のスライドが最後か否かで分岐
		if [ $current_slide_idx -lt $((NUM_SLIDES - 1)) ]; then
			# 現在のスライドが最後でない場合
			## セットされていない場合(セットされている場合の処理をジャンプで飛ばす)
			skip_next_inst_addr=$(add_addr $START_ADDR 3)
			echo "d -m $START_ADDR jmp $skip_next_inst_addr"; inc_saddr
			## セットされている場合(入力文字を読み出し、次のスライドのPDP-7命令列へジャンプ)
			echo "d -m $START_ADDR krb"; inc_saddr
			echo "d -m $START_ADDR jmp __NEXT_SLIDE_PROG_ADDR__"; inc_saddr
			### → "__NEXT_SLIDE_PROG_ADDR__"の部分は次のスライドのPDP-7命令列生成時に置換する
		else
			# 現在のスライドが最後の場合
			## セットされていない場合(セットされている場合の処理をジャンプで飛ばす)
			skip_next_inst_addr=$(add_addr $START_ADDR 2)
			echo "d -m $START_ADDR jmp $skip_next_inst_addr"; inc_saddr
			## セットされている場合(入力文字を読み出すのみ)
			echo "d -m $START_ADDR krb"; inc_saddr
		fi

		# ライトペンのタッチ判定に応じた処理
		## ライトペンが描画箇所に触れているか？
		echo "d -m $START_ADDR idsp"; inc_saddr
		## 現在のスライドが最初か否かで分岐
		if [ $current_slide_idx -gt 0 ]; then
			# 現在のスライドが最初でない場合
			## 触れていない場合(触れてる場合の処理をジャンプで飛ばす)
			skip_next_inst_addr=$(add_addr $START_ADDR 3)
			echo "d -m $START_ADDR jmp $skip_next_inst_addr"; inc_saddr
			## 触れている場合(割り込みをクリアし、前のスライドのPDP-7命令列へジャンプ)
			echo "d -m $START_ADDR idrs"; inc_saddr
			echo "d -m $START_ADDR jmp $prev_slide_prog_addr"; inc_saddr
		else
			# 現在のスライドが最初の場合
			## 触れていない場合(触れてる場合の処理をジャンプで飛ばす)
			skip_next_inst_addr=$(add_addr $START_ADDR 2)
			echo "d -m $START_ADDR jmp $skip_next_inst_addr"; inc_saddr
			## 触れている場合(割り込みをクリアするのみ)
			echo "d -m $START_ADDR idrs"; inc_saddr
		fi

		echo "d -m $START_ADDR idsi"; inc_saddr
		echo "d -m $START_ADDR jmp $draw_loop_saddr"; inc_saddr
		echo "d -m $START_ADDR jmp $slide_prog_saddr"; inc_saddr
	} >>${RESULT_SIMH}

	prev_slide_prog_addr=$slide_prog_saddr
	current_slide_idx=$((current_slide_idx + 1))
done

# 環境設定・実行開始
cat <<EOF >>${RESULT_SIMH}
set g2out disabled
set dpy enabled
go $PROG_START_ADDR
exit
EOF
