@echo off
odin build src/game/asset_packer -o:aggressive -out:build/asset_packer.exe -vet-style -vet-shadowing -vet-using-stmt -vet-using-param -vet-semicolon
