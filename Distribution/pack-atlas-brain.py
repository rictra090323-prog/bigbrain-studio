"""Pack the five untextured meshes from the Innerscene CC0 Brain GLB for Atlas."""
import json
from pathlib import Path
import struct
import sys


def pack(source, destination):
    data = source.read_bytes()
    magic, version, length, json_size, json_type = struct.unpack_from("<4sIIII", data)
    if (magic, version, length, json_type) != (b"glTF", 2, len(data), 0x4E4F534A):
        raise ValueError("Expected a glTF 2 binary with embedded geometry.")
    gltf = json.loads(data[20:20 + json_size])
    binary = memoryview(data)[28 + json_size:]

    def accessor(index, layout):
        item = gltf["accessors"][index]
        view = gltf["bufferViews"][item["bufferView"]]
        stride = view.get("byteStride", layout.size)
        offset = view.get("byteOffset", 0) + item.get("byteOffset", 0)
        return (layout.unpack_from(binary, offset + i * stride) for i in range(item["count"]))

    vertices, indices = [], []
    for mesh in gltf["meshes"]:
        for primitive in mesh["primitives"]:
            attrs = primitive["attributes"]
            positions = accessor(attrs["POSITION"], struct.Struct("<3f"))
            normals = accessor(attrs["NORMAL"], struct.Struct("<3f"))
            indices.extend(len(vertices) + index for (index,) in accessor(primitive["indices"], struct.Struct("<H")))
            vertices.extend(zip(positions, normals))
    if len(vertices) >= 65536 or len(indices) % 3:
        raise ValueError("The Atlas mesh needs indexed triangles and 16-bit vertex indices.")

    # Coordinates are right, up and front. Center the cortex above the stem.
    def quantize(value):
        return round(32767 * min(1, max(-1, value)))

    output = bytearray(struct.pack("<4sII", b"BBM1", len(vertices), len(indices)))
    for (x, y, z), normal in vertices:
        output.extend(struct.pack("<6h", *(quantize(v) for v in (12*x, 12*(y - 0.066), 12*z, *normal))))
    output.extend(struct.pack(f"<{len(indices)}H", *indices))
    destination.write_bytes(output)
    print(f"{len(vertices)} vertices, {len(indices) // 3} triangles, {len(output)} bytes")


if __name__ == "__main__":
    pack(Path(sys.argv[1]), Path(sys.argv[2]))
