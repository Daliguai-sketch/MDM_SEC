import math

def compare(data_len_byte, calc_list, out_data_byte_offset, golden_list):
    print("###############CHECK_OUT_FIFO##############")
    rem_byte = out_data_byte_offset % 4
    word_num = math.floor(out_data_byte_offset / 4)
    last_idx = math.ceil(data_len_byte / 4) - 1
    last_rem = data_len_byte % 4
    if len(calc_list) == len(golden_list):
        for i in range(len(calc_list)):
            if i < word_num:
                continue
            elif i == word_num and rem_byte:
                calc_bytes = 0
                golden_bytes = 0
                match(rem_byte):
                    case 1:
                        calc_bytes = calc_list[i] & 0x00FFFFFF
                        golden_bytes = golden_list[i] & 0x00FFFFFF
                    case 2:
                        calc_bytes = calc_list[i] & 0x0000FFFF
                        golden_bytes = golden_list[i] & 0x0000FFFF
                    case 3:
                        calc_bytes = calc_list[i] & 0x000000FF
                        golden_bytes = golden_list[i] & 0x000000FF
                if calc_bytes != golden_bytes:
                    print("Check Failed: Output FIFO data != Golden data, data_idx = " + str(i) + " !")
                    return False
            elif i == last_idx and last_rem :
                calc_bytes = 0
                golden_bytes = 0
                match(last_rem):
                    case 1:
                        calc_bytes = calc_list[i] & 0xFF000000
                        golden_bytes = golden_list[i] & 0xFF000000
                    case 2:
                        calc_bytes = calc_list[i] & 0xFFFF0000
                        golden_bytes = golden_list[i] & 0xFFFF0000
                    case 3:
                        calc_bytes = calc_list[i] & 0xFFFFFF00
                        golden_bytes = golden_list[i] & 0xFFFFFF00
                if calc_bytes != golden_bytes:
                    print("Check Failed: Output FIFO data [" + f"0x{calc_list.data[i]:08x}" + "]!= Golden data [" + f"0x{golden_list.data[i]:08x}" + "], data_idx = " + str(i) + " !")
                    return False
            else:
                if calc_list[i] != golden_list[i]:
                    print("Check Failed: Output FIFO data [" + f"0x{calc_list[i]:08x}" + "]!= Golden data [" + f"0x{golden_list[i]:08x}" + "], data_idx = " + str(i) + " !")
                    return False
    else:
        print("Check Failed: Output FIFO data length " + str(len(calc_list)) + " is not same as golden " + str(len(golden_list)) + " !")
        return False

    return True
        

def checksum(calc_output_data, out_data_byte_offset, golden_data, mac_check_en, calc_mac_data, mac_golden):
    a = 0
    outfifo_data = []
    if out_data_byte_offset :
        rem_byte = out_data_byte_offset % 4
        word_num = math.floor(out_data_byte_offset / 4)
        for i in range(word_num):
            outfifo_data.append(0)
        for i in range(len(calc_output_data.data)):
            if rem_byte:
                rem_word = 0
                match (rem_byte):
                    case 1:
                        comb_word = rem_word << 24 | calc_output_data.data[i] & 0xFFFFFF00
                        rem_word = calc_output_data.data[i] & 0xFF
                    case 2:
                        comb_word = rem_word << 16 | calc_output_data.data[i] & 0xFFFF0000
                        rem_word = calc_output_data.data[i] & 0xFFFF
                    case 3:
                        comb_word = rem_word << 8 | calc_output_data.data[i] & 0xFF000000
                        rem_word = calc_output_data.data[i] & 0xFFFF
                outfifo_data.append(comb_word)
                if i == len(calc_output_data.data) - 1:
                    comb_word = rem_word << 8(4-rem_byte)
                    outfifo_data.append(comb_word)

            else:
                outfifo_data.append(calc_output_data.data[i])
    else:
        outfifo_data = calc_output_data.data

    # checker
    if (compare(calc_output_data.data_len,outfifo_data,out_data_byte_offset,golden_data)):
        print("Check Passed !")
    if mac_check_en:
        print("###############CHECK_MAC##############")
        if calc_mac_data.data[0] == mac_golden.data[0]:
            print("Check Passed: calc_mac: [" + f"0x{calc_mac_data.data[0]:08x}" + "]")
        else:
            print("Check Failed: calc_mac: [" + f"0x{calc_mac_data.data[0]:08x}" + "] but palint_mac: ["+ f"0x{mac_golden.data[0]:08x}" + "]")
        a = 0


