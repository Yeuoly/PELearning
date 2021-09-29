    .386
    .model flat,stdcall

option casemap:none

include     windows.inc
include     user32.inc
includelib  user32.lib
include     kernel32.inc
includelib  kernel32.lib
include     comdlg32.inc
includelib  comdlg32.lib

; 宏，相当于重命名，将1000命名为 ICO_MAIN
ICO_MAIN equ 1000
DLG_MAIN equ 1000
IDC_INFO equ 1001
IDM_MAIN equ 5000
IDM_OPEN equ 5001
IDM_EXIT equ 5002

IDM_1    equ 4000
IDM_2    equ 4001
IDM_3    equ 4002
IDM_4    equ 4003

; data段
    .data
hInstance   dd ? ; 进程实例句柄
hRichEdit   dd ? ; 富文本动态链接库句柄
hWinMain    dd ? ; 窗口句柄
hWinEdit    dd ? ; 文本控件句柄
totalSize   dd ? ; 文件大小
lpMemory    dd ? ; 内存映像文件在内存的起始位置
szFileName  dd MAX_PATH dup(?) ; 

lpServicesBuffer         db 100 dup(0)   ;所有内容
bufDisplay               db 50 dup(0)      ;第三列ASCII码字符显示
szBuffer                 db 200 dup(0)       ;临时缓冲区
lpszFilterFmt4           db  '%08x  ',0
lpszManyBlanks           db  '  ',0
lpszBlank                db  ' ',0
lpszSplit                db  '-',0
lpszScanFmt              db  '%02x',0
lpszHexArr               db  '0123456789ABCDEF',0
lpszReturn               db  0dh,0ah,0
lpszDoubleReturn         db  0dh,0ah,0dh,0ah,0
lpszOut1                 db  '文件大小：%d',0
dwStop                   dd  0
    
    .const
szDllEdit                db 'RichEd20.dll',0
szClassEdit              db 'RichEdit20A',0
szFont                   db 'Consolas',0
szExtPe                  db 'PE File',0,'*.exe;*.dll;*.scr;*.fon;*.drv',0
                         db 'All Files(*.*)',0,'*.*',0,0
szErr                    db '文件格式错误!',0
szErrFormat              db '操作文件时出现错误!',0


    .code
;------------------
; 错误Handler
;------------------
_Handler proc _lpExceptionRecord,_lpSEH,\
              _lpContext,_lpDispathcerContext
  pushad
  mov esi,_lpExceptionRecord
  mov edi,_lpContext
  assume esi:ptr EXCEPTION_RECORD,edi:ptr CONTEXT
  mov eax,_lpSEH
  push [eax+0ch]
  pop [edi].regEbp
  push [eax+8]
  pop [edi].regEip
  push eax
  pop [edi].regEsp
  assume esi:nothing,edi:nothing
  popad
  mov eax,ExceptionContinueExecution
  ret
_Handler endp

;---------------------
; 往文本框中追加文本
;---------------------
_appendInfo proc _lpsz
  local @stCR:CHARRANGE

  pushad
  invoke GetWindowTextLength,hWinEdit
  mov @stCR.cpMin,eax  ;将插入点移动到最后
  mov @stCR.cpMax,eax
  invoke SendMessage,hWinEdit,EM_EXSETSEL,0,addr @stCR
  invoke SendMessage,hWinEdit,EM_REPLACESEL,FALSE,_lpsz
  popad
  ret
_appendInfo endp

;---------------------
; 打开文件
;---------------------
_openFile proc
    local @stOF:OPENFILENAME
    local @hFile, @hMapFile
    local @bufTemp1   ;十六进制字节码
    local @bufTemp2   ;第一行
    local @dwCount    ;计数，逢16重新计
    local @dwCount1   ;地址序号
    local @dwBlanks   ;最后一行空格数

    invoke RtlZeroMemory, addr @stOF, sizeof @stOF
    mov @stOF.lStructSize, sizeof @stOF

    push hWinMain
    pop @stOF.hwndOwner
    mov @stOF.lpstrFile, offset szFileName
    mov @stOF.nMaxFile, MAX_PATH
    mov @stOF.Flags, OFN_PATHMUSTEXIST or OFN_FILEMUSTEXIST
    invoke GetOpenFileName, addr @stOF ;让用户打开文件

    .if !eax
        jmp @F
    .endif

    ;创建或者打开文件，在上一步GetOpenFile之前
    ;mov @stOF.lpstrFile, offset szFileName
    ;这个操作将结构体中的文件名指针替换为了我们的指针
    ;从而在GetOpenFile的时候API将文件名写入了szFileName
    invoke CreateFile, addr szFileName, GENERIC_READ, \
        FILE_SHARE_READ or FILE_SHARE_WRITE, NULL, \
        OPEN_EXISTING, FILE_ATTRIBUTE_ARCHIVE, NULL
    
    .if eax != INVALID_HANDLE_VALUE
        mov @hFile, eax
        invoke GetFileSize, eax, NULL
        mov totalSize, eax

        .if eax
            invoke CreateFileMapping, @hFile, \
                NULL, PAGE_READONLY, 0, 0, NULL ;内存映射文件
            .if eax
                mov @hMapFile, eax
                invoke MapViewOfFile, eax, \ ;获取映射地址
                    FILE_MAP_READ, 0, 0, 0
                .if eax
                    mov lpMemory, eax
                    assume fs:nothing
                    push ebp
                    push offset _ErrFormat
                    push offset _Handler
                    push fs:[0]
                    mov fs:[0], esp
                    ;处理文件
                    ;缓冲区初始化
                    invoke RtlZeroMemory,addr @bufTemp1,10
                    invoke RtlZeroMemory,addr @bufTemp2,20
                    invoke RtlZeroMemory,addr lpServicesBuffer,100
                    invoke RtlZeroMemory,addr bufDisplay,50

                    mov @dwCount,1
                    mov esi,lpMemory
                    mov edi,offset bufDisplay

                    ; 将第一列写入lpServicesBuffer
                    mov @dwCount1,0
                    invoke wsprintf,addr @bufTemp2,addr lpszFilterFmt4,@dwCount1
                    invoke lstrcat,addr lpServicesBuffer,addr @bufTemp2

                    ;求最后一行的空格数（16－长度％16）*3
                    xor edx,edx
                    mov eax,totalSize
                    mov ecx,16
                    div ecx
                    mov eax,16
                    sub eax,edx
                    xor edx,edx
                    mov ecx,3
                    mul ecx
                    mov @dwBlanks,eax

                    ;invoke wsprintf,addr szBuffer,addr lpszOut1,totalSize
                    ;invoke MessageBox,NULL,addr szBuffer,NULL,MB_OK

                    .while TRUE
                        .if totalSize==0  ;最后一行
                            ;填充空格
                            .while TRUE
                                .break .if @dwBlanks==0
                                invoke lstrcat,addr lpServicesBuffer,addr lpszBlank
                                dec @dwBlanks
                            .endw
                            ;第二列与第三列中间的空格
                            invoke lstrcat,addr lpServicesBuffer,addr lpszManyBlanks  
                            ;第三列内容
                            invoke lstrcat,addr lpServicesBuffer,addr bufDisplay
                            ;回车换行符号
                            invoke lstrcat,addr lpServicesBuffer,addr lpszReturn
                            .break
                        .endif
                        ;将al翻译成可以显示的ascii码字符,注意不能破坏al的值
                        mov al,byte ptr [esi]
                        .if al>20h && al<7eh
                            mov ah,al
                        .else        ;如果不是ASCII码值，则显示“.”
                            mov ah,2Eh
                        .endif
                        ;写入第三列的值
                        mov byte ptr [edi],ah

                        ;win2k不支持al字节级别，经常导致程序无故结束，
                        ;因此用以下方法替代
                        ;invoke wsprintf,addr @bufTemp1,addr lpszFilterFmt3,al
                                    
                        mov bl,al
                        xor edx,edx
                        xor eax,eax
                        mov al,bl
                        mov cx,16
                        div cx   ;结果高位在al中，余数在dl中

                        ;组合字节的十六进制字符串到@bufTemp1中，类似于：“7F \0”
                        push edi
                        xor bx,bx
                        mov bl,al
                        movzx edi,bx
                        mov bl,byte ptr lpszHexArr[edi]
                        mov byte ptr @bufTemp1[0],bl

                        xor bx,bx
                        mov bl,dl
                        movzx edi,bx
                        mov bl,byte ptr lpszHexArr[edi]
                        mov byte ptr @bufTemp1[1],bl
                        mov bl,20h
                        mov byte ptr @bufTemp1[2],bl
                        mov bl,0
                        mov byte ptr @bufTemp1[3],bl
                        pop edi

                        ; 将第二列写入lpServicesBuffer
                        invoke lstrcat,addr lpServicesBuffer,addr @bufTemp1

                        .if @dwCount==16   ;已到16个字节，
                            ;第二列与第三列中间的空格
                            invoke lstrcat,addr lpServicesBuffer,addr lpszManyBlanks
                            ;显示第三列字符
                            invoke lstrcat,addr lpServicesBuffer,addr bufDisplay        
                            ;回车换行
                            invoke lstrcat,addr lpServicesBuffer,addr lpszReturn

                            ;写入内容
                            invoke _appendInfo,addr lpServicesBuffer
                            invoke RtlZeroMemory,addr lpServicesBuffer,100           

                            .break .if dwStop==1

                            ;显示下一行的地址
                            inc @dwCount1
                            invoke wsprintf,addr @bufTemp2,addr lpszFilterFmt4,\
                                @dwCount1
                            invoke lstrcat,addr lpServicesBuffer,addr @bufTemp2
                            dec @dwCount1

                            mov @dwCount,0
                            invoke RtlZeroMemory,addr bufDisplay,50
                            mov edi,offset bufDisplay
                            ;为了能和后面的inc edi配合使edi正确定位到bufDisplay处
                            dec edi
                        .endif

                        dec totalSize
                        inc @dwCount
                        inc esi
                        inc edi
                        inc @dwCount1
                    .endw

                    ;添加最后一行
                    invoke _appendInfo,addr lpServicesBuffer

                    ;处理结束
                    jmp _ErrorExit
    _ErrFormat:
                    invoke MessageBox, hWinMain, offset szErrFormat, NULL, MB_OK
    _ErrorExit:
                    pop fs:[0]
                    add esp, 0ch
                    invoke UnmapViewOfFile, lpMemory
                .endif
                invoke CloseHandle, @hMapFile
            .endif
            invoke CloseHandle, @hFile
        .endif
    .endif
    @@:
        ret
_openFile endp

; init初始化函数
_init proc
    local @stCf:CHARFORMAT

    invoke GetDlgItem, hWinMain, IDC_INFO
    mov hWinEdit, eax

    invoke LoadIcon, hInstance, ICO_MAIN
    invoke SendMessage, hWinMain, WM_SETICON, ICON_BIG, eax

    invoke SendMessage, hWinEdit, EM_SETTEXTMODE, TM_PLAINTEXT, 0
    invoke RtlZeroMemory, addr @stCf, sizeof @stCf

    mov @stCf.cbSize, sizeof @stCf
    mov @stCf.yHeight, 9 * 20
    mov @stCf.dwMask, CFM_FACE or CFM_SIZE or CFM_BOLD
    invoke lstrcpy, addr @stCf.szFaceName, addr szFont
    invoke SendMessage, hWinEdit, EM_SETCHARFORMAT, 0, addr @stCf
    invoke SendMessage, hWinEdit, EM_EXLIMITTEXT, 0, -1
    ret
_init endp

_ProcDlgMain proc uses ebx edi esi hWnd, wMsg, wParam, lParam
    mov eax, wMsg
    .if eax == WM_CLOSE ; 关闭
        invoke EndDialog, hWnd, NULL
    .elseif eax == WM_INITDIALOG ; 初始化
        push hWnd
        pop  hWinMain
        call _init
    .elseif eax == WM_COMMAND
        mov eax, wParam
        .if  eax == IDM_EXIT
            invoke EndDialog, hWnd, NULL
        .elseif eax == IDM_OPEN
            invoke CreateThread, NULL, 0, addr _openFile, offset hWinMain, 0, NULL
        .elseif eax == IDM_1
        .elseif eax == IDM_2
        .elseif eax == IDM_3
        .endif
    .else
        mov eax, FALSE
        ret
    .endif
    mov eax, TRUE
    ret
_ProcDlgMain endp

start:
    invoke LoadLibrary, offset szDllEdit
	mov hRichEdit, eax
	invoke GetModuleHandle, NULL
	mov hInstance, eax
	invoke DialogBoxParam, hInstance, DLG_MAIN,NULL, offset _ProcDlgMain, NULL
	invoke FreeLibrary, hRichEdit
	invoke ExitProcess, NULL
end start