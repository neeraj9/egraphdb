@rem Tune your paths according to installations
@rem
@rem Setup windows commandline tools for x64_64 (amd64)
call "C:\Program Files (x86)\Microsoft Visual Studio 12.0\VC\vcvarsall.bat" amd64

@rem Setup PATH for Git
set PATH=%PATH%;%USERPROFILE%\AppData\Local\Programs\Git\cmd

@rem Setup PATH for Erlang (64bit)
@rem IMPORTANT: Install 64bit Erlang so that it matches with VC vars above
set PATH=%PATH%;C:\Program Files\erl10.0.1\bin

@rem Now you can compile and run Project as follows:
@rem rebar3.cmd as test shell
@rem
