import os
import sys

PROJECT_ROOT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..")
)

sys.path.insert(0, PROJECT_ROOT)

from sec_core.snow3g import sec_snow3g_core as snow


OUTPUT_DIR = os.path.join(
    PROJECT_ROOT,
    "rtl_gpt",
    "rtl",
    "snow3g"
)

os.makedirs(OUTPUT_DIR, exist_ok=True)


def generate_table_module(
    module_name,
    output_width,
    values
):
    path = os.path.join(
        OUTPUT_DIR,
        module_name + ".v"
    )

    hex_width = output_width // 4

    with open(path, "w", encoding="utf-8") as f:

        f.write(
            f"module {module_name} (\n"
            f"    input  wire [7:0] i_data,\n"
            f"    output reg [{output_width-1}:0] o_data\n"
            f");\n\n"
        )

        f.write("always @(*) begin\n")
        f.write("    case (i_data)\n")

        for i, value in enumerate(values):
            f.write(
                f"        8'h{i:02X}: "
                f"o_data = {output_width}'h"
                f"{value:0{hex_width}X};\n"
            )

        f.write(
            f"        default: o_data = "
            f"{output_width}'h0;\n"
        )

        f.write("    endcase\n")
        f.write("end\n\n")
        f.write("endmodule\n")

    print("Generated:", path)


def main():

    # Rijndael S-Box
    generate_table_module(
        "snow3g_sbox_sr",
        8,
        snow.SR
    )

    # SNOW3G SQ S-Box
    generate_table_module(
        "snow3g_sbox_sq",
        8,
        snow.SQ
    )

    # MULalpha
    mulalpha_values = [
        snow.MULalpha(i)
        for i in range(256)
    ]

    generate_table_module(
        "snow3g_mulalpha",
        32,
        mulalpha_values
    )

    # DIValpha
    divalpha_values = [
        snow.DIValpha(i)
        for i in range(256)
    ]

    generate_table_module(
        "snow3g_divalpha",
        32,
        divalpha_values
    )


if __name__ == "__main__":
    main()