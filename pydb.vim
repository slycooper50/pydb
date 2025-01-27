vim9script
# Plugin for Python pdb
def Echoerr(msg: string)
  echohl ErrorMsg | echom $'[termdebug] {msg}' | echohl None
enddef

def Echowarn(msg: string)
  echohl WarningMsg | echom $'[termdebug] {msg}' | echohl None
enddef

command -nargs=* -complete=file -bang PyDb StartPypdb(<bang>0, <f-args>)
var octproc_id: number
var pybfnr: number
var commbfnr: number
var outbfnr: number
var py_win: number
var comm_win: number
var out_win: number
var srcwin: number
var brkpts: dict<any>
var brkpts_sgns: list<number>
var pybin: string
var err: string
var vvertical: bool
var allleft: bool 
var out_msg: list<string>
var rec_msg: bool
var brk_cnt: number
var pcln: number
var pcid: number
var stack: list<any>
var fname: string
var brk_sgns: list<string>

def Highlight(init: bool, old: string, new: string)
  var default = init ? 'default ' : ''
  if new ==# 'light' && old !=# 'light'
    exe $"hi {default}debugPC term=reverse ctermbg=lightblue guibg=lightblue"
  elseif new ==# 'dark' && old !=# 'dark'
    exe $"hi {default}debugPC term=reverse ctermbg=darkblue guibg=darkblue"
  endif
enddef

def InitHighlight()
  Highlight(true, '', &background)
  hi default debugBreakpoint term=reverse ctermbg=red guibg=red
  hi default debugBreakpointDisabled term=reverse ctermbg=gray guibg=gray
	hi default frame cterm=bold ctermfg=12 guifg=DodgerBlue
	hi default link curr_frame WarningMsg
enddef

def InitVars()
	pybin = "python"
	vvertical = true
	allleft = false 
	brkpts = {}
	brkpts_sgns = []
	rec_msg = false
	brk_cnt = 0
	pcln = 0
	pcid = 14
	stack = []
	fname = ''
enddef

def CommCB(chan: channel, msg: string)
	if msg[0] =~ 'Breakpoint'
		#HandleBreak(msg)
	elseif (msg =~ '^\s\+/' )
		HandleStack(msg)
	elseif (msg[0] =~ '>' || msg =~ '\s*--Call--')
		HandleStep(msg)
	endif
enddef

def InitAutocmd()
  augroup TermDebug
    autocmd!
    autocmd ColorScheme * InitHighlight()
  augroup END
enddef

def QuoteArg(x: string): string
  # Find all the occurrences of " and \ and escape them and double quote
  # the resulting string.
  return printf('"%s"', x ->substitute('[\\"]', '\\&', 'g'))
enddef

def SetBreakpoint(at: string)
	var AT = empty(at) ? $"{QuoteArg(expand('<cword>'))}, {QuoteArg($"{line('.')}")}" : at
	var cmd = $"brk = b ({AT}), file =file_in_loadpath({QuoteArg(expand('<cword>') .. '.m')})\r"
	term_sendkeys(pybfnr, cmd)
enddef

def HandleBreak(msg: list<string>)
	inputstr = split(msg, "\r")
	var brkln = 0
	fname = trim(matchstr(inputstr[1], '=\s*\zs.*'))
	brkln = str2nr(split(inputstr[0], '=')[1])
	brk_cnt += 1
	var label = slice(printf('%02X', brk_cnt), 0, 2)
	if has_key(brkpts, fname)
		if index(brkpts[fname], brkln) == -1 
			brkpts[fname] = add(brkpts[fname], brkln)
		endif
	else
		brkpts[fname] = [brkln]
	endif
	if win_gotoid(srcwin)
		if expand('%:p') != fnamemodify(fname, ':p')
			exe $'edit {fname}'
		endif
		exe $":{brkln}"
		sign_define($'dbgbrk{brkln}', {text: label, texthl: "debugBreakpoint"})
		sign_place(0, 'Breakpoint', $'dbgbrk{brkln}', fname, {lnum: brkln})
	endif
enddef

def HandleStep(msg: string)
	fname = matchstr(msg, '\(\s*--Call--\_.\)\?>\s*\zs.\+\ze(\d\+)')
	pcln = str2nr(matchstr(msg, "(\\zs\\s*\\d*)"))
	if win_gotoid(srcwin)
		if expand('%:p') != fnamemodify(fname, ':p')
			exe $'edit {trim(fname)}'
		endif
		exe $":{pcln}"
		sign_unplace('TermDebug', {id: pcid})
		sign_place(pcid, 'TermDebug', 'debugPC', '%', {lnum: pcln})
	endif
	#HandleStack(msg)
enddef

def HandleStack(msg: string)
	stack = []
	var lines = []
	var frames = []
	lines = split(msg, "\r")
	frames = filter(lines, 'v:val =~ "/"')
	for frameln in frames
		var frame = substitute(frameln, '[[:cntrl:]]', '', 'g')
		var func = matchstr(frame, '(\d*)\zs.*\ze(.*)')
		var active = 0
		if frame =~ '>\s*/'
			active = 1	
		endif
		var ln = matchstr(frame, '(\zs\d*\ze)')
		fname = matchstr(frame, '\s*>\?\s*\zs.*\ze(\d\+)')
		var entry = {'func': func, 'ln': ln, 'fname': fname, 'active': active}
		if !empty(func)
			add(stack, entry)
		endif
	endfor
	lines = []
	for frame in stack
		add(lines, frame['fname'] .. repeat(' ', 4) .. frame['ln'])
		if frame['active']
			matchadd('curr_frame', frame['fname'], 10, -1, {window: out_win})
		else
			matchadd('frame', frame['fname'], 10, -1, {window: out_win})
		endif
	endfor
	#exe $":{outbfnr}bufdo %d"
	deletebufline(outbfnr, 1, "$")
	setbufline(outbfnr, 1, lines)
enddef

def Up(count: number)
	var cmd = $"up {count}\r"
	term_sendkeys(pybfnr, cmd)
enddef

def Down(count: number)
	var cmd = $"down {count}\r"
	term_sendkeys(pybfnr, cmd)
enddef

def InstallCommands()
  command! -nargs=? Break  SetBreakpoint(<q-args>)
  #command Clear  ClearBreakpoint()
  #command Step  SendResumingCommand('-exec-step')
  #command Over  SendResumingCommand('-exec-next')
  #command -nargs=? Until  Until(<q-args>)
  #command Finish  SendResumingCommand('-exec-finish')
  #command -nargs=* Run  Run(<q-args>)
  #command -nargs=* Arguments  SendResumingCommand('-exec-arguments ' .. <q-args>)
  #command Stop StopCommand()
  #command Continue ContinueCommand()
  #command -nargs=* Frame  Frame(<q-args>)
  command! -count=1 Up  Up(<count>)
  command! -count=1 Down  Down(<count>)
  #command -range -nargs=* Evaluate  Evaluate(<range>, <q-args>)
  #command Gdb  win_gotoid(gdbwin)
  #command Program  GotoProgram()
  #command Source  GotoSourcewinOrCreateIt()
  #command Var  GotoVariableswinOrCreateIt()
  #command Winbar  InstallWinbar(true)
enddef

def Mapping()
	nnoremap <expr> <F9> $':call term_sendkeys({pybfnr}, "continue\r")<CR>'
	nnoremap <expr> <F8> $':call term_sendkeys({pybfnr}, "next\r")<CR>'
	nnoremap <expr> <F6> $':call term_sendkeys({pybfnr}, "return\r")<CR>'
	nnoremap <expr> <F5> $':call term_sendkeys({pybfnr}, "step\r")<CR>'
	nnoremap <expr> <C-L> $':call term_sendkeys({pybfnr},' .. "'print(" .. '"\033c")' .. "'" .. '.. "\r")<CR>'
	nnoremap <expr> ,<Space> $':call term_sendkeys({pybfnr},"bt" .. "\r")<CR>'
  nnoremap <C-PageUp> :Up<CR>
  nnoremap <C-PageDown> :Down<CR>
enddef

def Exit()
  sign_unplace('TermDebug')
  sign_undefine('debugPC')
  sign_undefine(brk_sgns->map("'debugBreakpoint' .. v:val"))
enddef

###################################################################################
# Main function #
def StartPypdb(bang: bool, pyfile: string)
	InitVars()
	if !executable(pybin)
		err = "Could not find Python executable. "
		echoe err
		return
	endif

  # Assume current window is the source code window
  srcwin = win_getid()

	#################################
	### Create Communication PTY ###
	commbfnr = term_start('NONE', {term_name: "Python Communication", vertical: vvertical, callback: 'CommCB'})
	exe ":set nobl"
	var commpty = job_info(term_getjob(commbfnr))['tty_out']
	comm_win = win_getid()
	#############################
	#### Create Output Buffer ####
	outbfnr = bufadd("Python Output")
	bufload(outbfnr)
	exe $'new +set\ nobl|setl\ number&|setl\ fcs=eob:\\\\x20 {bufname(outbfnr)}|set bt=nowrite'
	out_win = win_getid()
  if vvertical
    # Assuming the source code window will get a signcolumn, use two more
    # columns for that, thus one less for the terminal window.
    exe $":{(&columns / 3 - 1)}wincmd |"
    if allleft
      # use the whole left column
      wincmd H
    endif
  endif
	##############################
	### Create Python Terminal ####
	pybfnr = term_start(pybin, {term_name: "Python", term_finish: 'close'})
											#out_io: 'file', out_name: commpty, err_io: 'file', err_name: commpty})
	py_win = win_getid()
	exe ":set nobl"
	term_sendkeys(pybfnr, $"import pdb; slypdb = pdb.Pdb(stdout=open('{commpty}', 'w'))\r")
	term_sendkeys(pybfnr, $"slypdb._run(pdb._ScriptTarget('{pyfile}'))\r")
	########################################
	##### Sign For Program Counter Line ####
  sign_define('debugPC', {linehl: 'debugPC'})
  # Install debugger commands in the text window.
  win_gotoid(srcwin)
	########################################
  InstallCommands()
	Mapping()
enddef

InitHighlight()
InitAutocmd()
