package service

import (
	"errors"
	"os"
	"path"
)

func syncDirectory(directory string) error {
	file, err := os.Open(directory)
	if err != nil {
		return err
	}
	return errors.Join(file.Sync(), file.Close())
}

func syncRootDirectory(root *os.Root, directory string) error {
	if directory == "" {
		directory = "."
	}
	file, err := root.Open(directory)
	if err != nil {
		return err
	}
	return errors.Join(file.Sync(), file.Close())
}

func syncRootDirectoryChain(root *os.Root, directory string) error {
	if directory == "" {
		directory = "."
	}
	for current := directory; ; current = path.Dir(current) {
		if err := syncRootDirectory(root, current); err != nil {
			return err
		}
		if current == "." {
			return nil
		}
	}
}
