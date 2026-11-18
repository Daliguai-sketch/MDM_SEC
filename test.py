from testbench.gen_aes_ctr_golden import gen_aes_ctr_stream
import testbench.gen_aes_cmac_golden as gen_aes_cmac_golden
import tool.gen_snow3g_tables as gen_snow3g_tables
import testbench.gen_snow3g_golden as gen_snow3g_golden
import testbench.gen_snow3g_mac_golden as gen_snow3g_mac_golden
import testbench.gen_zuc_sboxes as gen_zuc_sboxes
import testbench.gen_zuc_golden as gen_zuc_golden
import testbench.gen_zuc_mac_golden as gen_zuc_mac_golden
import testbench.gen_sec_enc_golden_3plaint as gen_sec_enc_golden_3plaint
import testbench.gen_sec_enc_golden as gen_sec_enc_golden
from Crypto.Cipher import AES
import testbench.gen_sec_int_golden as gen_sec_int_golden
import testbench.gen_sec_process_golden as gen_sec_process_golden
from testbench.gen_aes_cmac_golden import bytes_to_words,generate_mac_from_bytes
import testbench.gen_sec_process_multi_alg_golden as gen_sec_process_multi_alg_golden

if __name__ == "__main__":
    a = 0                 
    # input
    #key = [              
    #    0x4881FF48,      
    #    0x952C4910,      
    #    0x82C5B300,      
    #    0xABD6459F       
    #]
    #key = [        
    #    0xF1722635,
    #    0x58DA3019,
    #    0x44A74CF3,
    #    0x83FD23A2     
    #]                                    
    #gen_aes_ctr_stream(  
    #    key=key,         
    #    count=0x36AF6144,
    #    bearer=0x1F,     
    #    direction=1,     
    #    stream_num=6     
    #)
                       
    #gen_aes_cmac_golden.main()      
    #gen_snow3g_tables.main()
    #gen_snow3g_golden.main()
    #gen_snow3g_mac_golden.main()
    #gen_zuc_sboxes.main()
    #gen_zuc_golden.main()
    #gen_zuc_mac_golden.main()
    #key = bytes.fromhex(
    #    "F172263558DA301944A74CF383FD23A2"
    #)

    #block = bytes.fromhex(
    #    "36AF6144FC0000000000000000000000"
    #)
#
    #stream = AES.new(
    #    key,
    #    AES.MODE_ECB
    #).encrypt(block)
#
    #print("AES STREAM =", stream.hex().upper())


    #aes = AES.new(key, AES.MODE_ECB)
#
    #rtl_stream = bytes.fromhex(
    #    "9E20ED87A8B9100A44E02AC00947E663"
    #)
#
    #for counter in range(8192):
#
    #    block = (
    #        bytes.fromhex("36AF6144FC00000000000000")
    #        + counter.to_bytes(4, "big")
    #    )
#
    #    stream = aes.encrypt(block)
#
    #    if stream == rtl_stream:
    #        print("MATCH COUNTER =", counter)
    #        break
    #else:
    #    print("NO COUNTER MATCH")
#
    #gen_sec_enc_golden.main()
    #gen_sec_int_golden.main()
    #gen_sec_process_golden.main()
    gen_sec_process_multi_alg_golden.main()
    '''
    int_only = bytes(
        (i + 0x31) & 0xFF
        for i in range(13)
    )

    enc_data = bytes(
        (i + 0xA5) & 0xFF
        for i in range(21)
    )

    message = int_only + enc_data

    words = bytes_to_words(message)

    print("MESSAGE:", message.hex().upper())
    print("LENGTH:", len(message))

    for i, word in enumerate(words):
        print(f"WORD{i:02d}: {word:08X}")

    key = bytes.fromhex(
        "000102030405060708090A0B0C0D0E0F"
    )
    KEY1 = [       
        0x00010203,
        0x04050607,
        0x08090A0B,
        0x0C0D0E0F 
    ]              
    count = 0x36AF6144
    bearer = 31
    direction = 1

    int_only = bytes(
        (i + 0x31) & 0xFF
        for i in range(13)
    )

    enc_data = bytes(
        (i + 0xA5) & 0xFF
        for i in range(21)
    )

    message = int_only + enc_data

    mac = generate_mac_from_bytes(
        KEY1,
        count,
        bearer,
        direction,
        message
    )

    print("MESSAGE:", message.hex().upper())
    print("LENGTH:", len(message))
    print("MAC:", f"{mac:08X}")
    a = 0
    
    import sys
    import inspect

    sys.path.insert(0, "testbench")

    import testbench.gen_snow3g_mac_golden as snow
    import testbench.gen_zuc_mac_golden as zuc

    print("SNOW3G:")
    print(inspect.signature(snow.generate_mac))

    print("ZUC:")
    print(inspect.signature(zuc.generate_mac))

    import inspect

    sys.path.insert(0, "testbench")

    import testbench.gen_snow3g_golden as snow
    import testbench.gen_zuc_golden as zuc

    print("SNOW3G functions:")
    for name, obj in inspect.getmembers(snow, inspect.isfunction):
        print(name, inspect.signature(obj))

    print("\nZUC functions:")
    for name, obj in inspect.getmembers(zuc, inspect.isfunction):
        print(name, inspect.signature(obj))
'''