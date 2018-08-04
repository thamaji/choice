package main

import (
	"bufio"
	"bytes"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"

	prompt "github.com/c-bata/go-prompt"
	colorable "github.com/mattn/go-colorable"
	"github.com/mattn/go-tty"
	"golang.org/x/crypto/ssh/terminal"
)

var (
	Version  = ""
	Revision = ""
)

func main() {
	var help, version bool
	flag.BoolVar(&help, "h", false, "show help")
	flag.BoolVar(&version, "v", false, "show version")

	flag.Usage = func() {
		fmt.Println()
		fmt.Println("Usage: " + os.Args[0] + " [OPTIONS] [WORD...]")
		fmt.Println()
		fmt.Println("Choice some word from arguments or stdin")
		fmt.Println()
		fmt.Println("Options:")
		flag.CommandLine.PrintDefaults()
		fmt.Println()
	}

	flag.Parse()

	if help {
		flag.Usage()
		return
	}

	if version {
		fmt.Println(Version + " (" + Revision + ")")
		return
	}

	in := os.NewFile(uintptr(3), "")
	_, err1 := in.Stat()

	out := os.NewFile(uintptr(4), "")
	_, err2 := out.Stat()

	// go-prompt が固定で stdin,stdout を見てるので stdin,stdout を差し替えて起動しなおす
	if err1 != nil || err2 != nil {
		if err := ShiftRun(); err != nil {
			fmt.Fprintln(os.Stderr, err.Error())
			os.Exit(1)
		}
		return
	}

	if err := Suggest(in, out); err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		os.Exit(1)
	}
}

func ShiftRun() error {
	tty, err := tty.Open()
	if err != nil {
		return err
	}
	defer tty.Close()

	stdin := os.Stdin
	if terminal.IsTerminal(int(os.Stdin.Fd())) {
		r, w, err := os.Pipe()
		if err != nil {
			return err
		}
		w.Close()
		defer r.Close()

		stdin = r
	}

	self := exec.Command(os.Args[0], flag.Args()...)
	self.Stdin = tty.Input()
	self.Stdout = tty.Output()
	self.Stderr = os.Stderr
	self.ExtraFiles = []*os.File{stdin, os.Stdout}

	return self.Run()
}

func Suggest(in *os.File, out *os.File) error {
	words := flag.Args()

	r := bufio.NewReader(in)
	var line []byte
	for {
		buf, isPrefix, err := r.ReadLine()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}

		line = append(line, buf...)

		if isPrefix {
			continue
		}

		if len(line) > 0 {
			for _, field := range bytes.Fields(line) {
				words = append(words, string(field))
			}
		}

		line = line[:0]
	}

	suggests := make([]prompt.Suggest, 0, len(words))
	for _, word := range words {
		suggests = append(suggests, prompt.Suggest{Text: word})
	}
	text := prompt.Input("> ", func(doc prompt.Document) []prompt.Suggest {
		return prompt.FilterContains(suggests, doc.GetWordBeforeCursor(), true)
	})
	fmt.Fprint(colorable.NewColorable(os.Stdout), "\x1b[0m") // go-prompt 側でリセットしてくれないので、ここでリセット

	fmt.Fprintln(out, text)

	return nil
}
