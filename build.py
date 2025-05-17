import os
import sys
import pathlib
import subprocess

if len(sys.argv) != 2:
	config = "debug"
else:
	config = sys.argv[1]

cwd = os.getcwd()

flags = []
flags.append("-out:build/game.exe")
flags.append("-collection:third_party=third_party")
flags.append("-vet-style")
flags.append("-vet-shadowing")
flags.append("-vet-using-stmt")
flags.append("-vet-using-param")
flags.append("-vet-semicolon")

pack_asset = False

shader_src_dir = "src/shader"
shader_out_dir = "build/res/shader"

# set flags
match config.lower():
	case "debug":
		flags.append("-o:none")
		flags.append("-debug")
		flags.append("-subsystem:console")
		flags.append("-define:DEV_BUILD=true")
		pack_asset = False
	case "release":
		flags.append("-o:aggressive")
		flags.append("-subsystem:windows")
		flags.append("-define:DEV_BUILD=false")
		pack_asset = True
		# TODO: resource file


# make directory
if not os.path.exists("build") or not os.path.isdir("build"):
	os.mkdir("build")


print("-- Compiling shaders")
# clear shader build directory
for file in os.listdir(shader_out_dir):
	os.remove(os.path.join(shader_out_dir, file))

# compile shader
for file in os.listdir(shader_src_dir):
	glsl_path = os.path.join(shader_src_dir, file)

	stage = ""
	if "vert" in file:
		stage = "vertex"
	elif "frag" in file:
		stage = "fragment"

	result = subprocess.call([
		"glslc",
		f"-fshader-stage={stage}",
		glsl_path,
		"-o", f"{shader_out_dir}/{pathlib.Path(glsl_path).stem}.spv",
	])

	if result != 0:
		exit()


print("-- Reflecting shaders")
for file in os.listdir(shader_out_dir):
	spv_path = os.path.join(shader_out_dir, file)

	stage = ""
	if "vert" in file:
		stage = "vertex"
	elif "frag" in file:
		stage = "fragment"

	result = subprocess.call([
		"build/shadercross",
		spv_path,
		"-t", stage,
		"-s", "SPIRV",
		"-d", "JSON",
		"-o", f"{shader_out_dir}/{pathlib.Path(spv_path).stem}.meta",
	])

	if result != 0:
		exit()


print("-- Packing resources")
os.chdir("build")
subprocess.call([
	"asset_packer",
	"-dir:res",
	f"-packed:{str(pack_asset).lower()}",
	"-pkg_name:game",
	"-out_def:../src/game/generated_asset_def.odin",
	"-out_packed:resource.dat",
])
os.chdir(cwd)


print("-- Building executable")
subprocess.call([
	"odin",
	"build",
	"src/game",
] + flags)
