# adatftpd-tester

The purpose of this program is to generate a whole series of binary files of various randomly selected sizes. Each byte of each file is also randomly generated.

An instance of 'atftp' will then be spawned and commanded to transfer each of the binary files into a local copy,  thus making a pair of files.

This program will then ensure the file pairs are identical, byte by byte.  Any file pairs that fail this test,  are retained after the program terminates and a program exit status of -1 shall be emitted.

Successful program completion shall emit a program exit status of 0.

Program requires 'atftp' to be installed via (on Ubuntu 19.10):

$ sudo apt install atftp

and in the PATH at the time of execution.
