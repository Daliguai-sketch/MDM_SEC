import os
from src.sec_class_define import golden_desc
from src.sec_class_define import data_desc
import re
import copy
import sys

def read_paradesc(file_path,para):
    with open(file_path,'r') as f:
        line_num = 1
        while True:
            line = f.readline()
            if not line:
                line_num = 0
                break
            line_int = int(line,16)
            if line_num == 1:
                para.direction = (line_int & 0x01000000) >> 24
                para.rbtype = (line_int & 0x00010000) >> 16
                para.bearer = (line_int & 0x00001F00) >> 8
                para.cmd = line_int & 0x0000001F
            elif line_num == 2:
                para.pdcp_sn_bit_size = (line_int & 0x1F000000) >> 24
                para.sdap_hdr = (line_int & 0x00FF0000) >> 16
                para.is_sdap_hdr_exit = (line_int & 0x00000100) >> 8
                para.interrupt = line_int & 0x00000001
            elif line_num == 3:
                para.pdcp_sn = line_int & 0x0003FFFF
            elif line_num == 4:
                para.counter = line_int & 0xFFFFFFFF
            # line5,6 not use
            elif line_num == 7:
                para.maci_out_byte_offset = (line_int & 0xFF000000) >> 24
                para.maci_in_byte_offset = (line_int & 0x00FF0000) >> 16
                para.int_alg_id = (line_int & 0x00000300) >> 8
                para.enc_alg_id = line_int & 0x00000003
            elif line_num == 8:
                para.cipher_out_byte_offset = (line_int & 0xFF000000) >> 24
                para.cipher_in_byte_offset = (line_int & 0x00FF0000) >> 16
                para.int_out_byte_offset = (line_int & 0x0000FF00) >> 8
                para.int_in_byte_offset = line_int & 0x000000FF
            #9-12, not use at python

            line_num += 1

def big_little_conv(hex_str_32):
    little = hex_str_32
    big = list(little)
    for i in range(4):
        j = 2*i
        big[j] = little[6-j]
        big[j+1] = little[8-j-1]
    return "".join(big)

def read_datadesc(file_path):
    len_byte = []
    with open(file_path,'r') as f:
        line_num = 1
        while True:
            line = f.readline()
            if not line:
                line_num = 0
                break
            line_int = int(line,16)
            if line_num % 6 == 2:
                len_byte.append(line_int & 0x0000FFFF)
            line_num += 1

    return len_byte

def read_key(file_path):
    key = []
    with open(file_path,'r') as f:
        line_num = 1
        while True:
            line = f.readline()
            if not line:
                line_num = 0
                break
            big_conv = big_little_conv(line)
            line_hex = int(big_conv,16)
            key.append(line_hex)
        key.reverse()
    return key

def read_seg_data(file_path):
    seg_num = 0 
    data_list = []
    data = data_desc([],[],[],0)
    idx = 0
    with open(file_path,'r') as f:
        line_num = 1
        while True:
            line = f.readline()
            if not line:
                seg_num += 1
                data.last.pop()
                data.last.append(1)
                data_list.append(copy.deepcopy(data))
                data.clear()
                break
            if line[0] == '#':
                match = re.search(r"Seg(\d+)",line)
                if match:
                    idx = int(match.group(1))
                    if idx != 0:
                        seg_num += 1
                        data.last.pop()
                        data.last.append(1)
                        data_list.append(copy.deepcopy(data))
                        data.clear()
                continue
            big_conv = big_little_conv(line)
            line_hex = int(big_conv,16)
            data.data.append(line_hex)
            data.data_vld.append(1)
            data.last.append(0)
            line_num += 1
    return data_list,seg_num

def read_data(file_path):
    data_list = []
    with open(file_path,'r') as f:
        line_num = 1
        while True:
            line = f.readline()
            if not line:
                line_num = 0
                break
            if line[0] == '#':
                continue
            big_conv = big_little_conv(line)
            line_hex = int(big_conv,16)
            data_list.append(line_hex)
    return data_list

def read_tv_files(tv_path):
    if not os.path.exists(tv_path):
        print("TestVector [" + tv_path + "] Is not exists!")
        sys.exit()

    input = golden_desc()
    for root, dirs,files in os.walk(tv_path):
        print(files)
        for file in files:
            file_path = os.path.join(root,file)
            #paradesc
            if file == "SecParaDesc.txt":
                read_paradesc(file_path,input)
            #datadesc
            elif file == "SecDataDesc.txt":
                input.in_data_seg_len = read_datadesc(file_path)
            #cipher key
            elif file == "CipherKey.txt":
                input.cipher_key = read_key(file_path)
            elif file == "IntKey.txt":
                input.int_key = read_key(file_path)
            elif file == "SecInputData.txt":
                # 数据在file中 小端存储， 存储 0x78563412, 实际数值： 0x12345678
                input.in_data,input.in_data_seg_num = read_seg_data(file_path)
            elif file == "SecOutputData.txt":
                input.out_data = read_data(file_path)
        input.calc_len()
    return input


if __name__ == "__main__":
    a = 0
    tv_path = "..tv/cmd_d"