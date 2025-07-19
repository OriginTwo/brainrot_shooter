import os
import sys
import pathlib
import subprocess

def build_game():
	if len(sys.argv) != 2:
		config = "debug"
	else:
		config = sys.argv[1]

	cwd = os.getcwd()

	flags = []
	flags.append("-out:build/game.exe")
	flags.append("-define:SOKOL_USE_GL=true")
	flags.append("-collection:lib=lib")
	flags.append("-vet-style")
	flags.append("-vet-shadowing")
	flags.append("-vet-using-stmt")
	flags.append("-vet-using-param")
	flags.append("-vet-semicolon")

	pack_resource = False

	shader_src_dir = "src/shader"
	shader_out_dir = "src/game/shader"

	# set flags
	match config.lower():
		case "debug":
			print("-- Configuration: Debug")
			flags.append("-o:none")
			flags.append("-debug")
			flags.append("-subsystem:console")
			flags.append("-define:DEV_BUILD=true")
			pack_resource = False
		case "release":
			print("-- Configuration: Release")
			flags.append("-o:aggressive")
			flags.append("-subsystem:windows")
			flags.append("-define:DEV_BUILD=false")
			pack_resource = True
			# TODO: rc file


	print("-- Compiling shaders")
	# make shader build directory if not exist
	if not os.path.exists(shader_out_dir) or not os.path.isdir(shader_out_dir):
		os.mkdir(shader_out_dir)

	# clear shader build directory
	for file in os.listdir(shader_out_dir):
		os.remove(os.path.join(shader_out_dir, file))

	# compile shader
	for file in os.listdir(shader_src_dir):
		shader_path = pathlib.Path(shader_src_dir).joinpath(file)
		result = subprocess.call([
			"build/sokol-shdc",
			"--input",  shader_path.as_posix(),
			"--output", f"{shader_out_dir}/{shader_path.stem}.odin",
			"--slang",  "glsl430",
			"--format", "sokol_odin",
			"--no-log-cmdline",
		])

		if result != 0:
			exit()


	print("-- Packing resources")
	os.chdir("build")
	respack_args = [
		"respacker",
		"-dir:res",
		"-pkg_name:game",
		"-out_odin:../src/game/generated_resource.odin",
	]
	if pack_resource:
		respack_args.append("-out_pak:resource.pak")
	subprocess.call(respack_args)
	os.chdir(cwd)


	print("-- Building executable")
	subprocess.call([
		"odin",
		"build",
		"src/game/main",
	] + flags)


if __name__ == "__main__":
	# make directory
	if not os.path.exists("build") or not os.path.isdir("build"):
		os.mkdir("build")
	build_game()
