--[[
   Copyright (c) 2017 Sakai Satoru
   All rights reserved.
   
   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions are
   met:
   
   * Redistributions of source code must retain the above copyright
     notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
     copyright notice, this list of conditions and the following disclaimer
     in the documentation and/or other materials provided with the
     distribution.
   * Neither the name of the  nor the names of its
     contributors may be used to endorse or promote products derived from
     this software without specific prior written permission.
   
   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
   
]]--


--[[
    Lua習作（１）
    BASIC インタープリタ
]]--

--
--  作業領域
--
textpointer=0           -- インストラクションポインタ
wordmemory={}           -- テキスト格納領域
wordcounter=1           -- テキスト格納領域ポインタ
variable={}             -- 変数格納領域
textlabel={}            -- ラベル
gosubstack={}           -- gosubスタック
gosub_sp=0              -- gosubスタックポインタ
forstack={}             -- forスタック
for_sp=0                -- forスタックポインタ
if_counter=0            -- if構文解析用カウンタ
linenumber=0            -- ランタイム行番号保持
currlineno=""           -- ランタイム行番号取り出し

ERROR_SYNTAX=1
ERROR_ELSE=2
ERROR_NEXT=3
ERROR_RETURN=4
ERROR_DIV=5
ERROR_LABEL=6
ERROR_ILLEGAL=7

--
--  ifやforのネスティング飛ばし
--  マッチした場合はその次を返す。ミスマッチの場合はnilを返す。
--
--                              IF        ENDIF     ELSE
--                              FOR       NEXT
function SkipNesting( pointer, topcode, endcode1, endcode2 )
    while wordmemory[pointer] ~= nil do
        if (wordmemory[pointer] == endcode1) or
            (endcode2 ~= nil and wordmemory[pointer] == endcode2) then
            -- ペアマッチ
            pointer = pointer + 1
            return pointer
        end
        
        if wordmemory[pointer] == topcode then
            -- ネスティング
            -- "IF"を探索する場合は"ELSE"を無視する
            pointer = SkipNesting( pointer, topcode, endcode1, 
                            ((topcode == "IF") and nil or endcode2) )
        else
            pointer = pointer + 1
        end
    end
    -- ペアマッチなし
    return nil
end

function ErrorHandler( no, opt )
    local message = {
                "Syntax Error",
                "ELSE/ENDIF without IF",
                "NEXT without FOR",
                "RETURN without GOSUB",
                "Divide by ZERO",
                "Undefined Label",
                "Illegal function call"
            }
    io.write( string.format( "%s in %d", message[no], linenumber ))
    if opt ~= nil then
        io.write( " near "..opt )
    end
    print("")
    os.exit(1)
end


basic_word = {  
        LET     = function()
                    local vname;
                    vname = wordmemory[textpointer]
                    textpointer = textpointer + 1
                    if wordmemory[textpointer] ~= "=" then
                        ErrorHandler( ERROR_SYNTAX, "LET" )
                    else
                        textpointer = textpointer + 1
                        variable[vname] = Expression()
                    end
                  end;
                  
        IF      = function()
                    if_counter = if_counter + 1
                    if Expression("THEN") ~= 0 then
                        -- "真" なので "THEN"の次を指して戻る
                        return
                    else
                        -- "偽" なので "ELSE"を見つけるか、"ENDIF"まで進む
                        textpointer = SkipNesting(textpointer, 
                                                "IF", "ENDIF", "ELSE" )
                        if textpointer == nil then
                            ErrorHandler( ERROR_SYNTAX, "IF" )
                        end
                        if wordmemory[textpointer-1] == "ENDIF" then
                            -- ENDIFの場合はカウンタ処理の為、それ自身を
                            -- 指して戻る
                            textpointer = textpointer - 1
                        end
                    end
                  end;
                  
        ELSE    = function()
                    -- ELSEは直接参照されない
                    ErrorHandler( ERROR_ELSE, "ELSE" )
                  end;
                  
        ENDIF   = function()
                    if if_counter < 1 then
                        ErrorHandler( ERROR_ELSE, "ENDIF" )
                    end
                    if_counter = if_counter - 1
                  end;
                    
        FOR     = function()
                    -- "NEXT" の探索を省略
                    local ar={}
                    ar["name"] = wordmemory[textpointer]
                    basic_word["LET"]()
                    if wordmemory[textpointer] ~= "TO" then
                        ErrorHandler( ERROR_SYNTAX, "TO" )
                    end
                    textpointer = textpointer + 1
                    ar["endvalue"] = Expression()
                    if wordmemory[textpointer] == "STEP" then
                        textpointer = textpointer + 1
                        ar["step"] = Expression()
                    else
                        ar["step"] = 1
                    end
                    ar["top"]=textpointer
                    for_sp = for_sp + 1
                    forstack[for_sp]=ar    
                  end;

        NEXT    = function()
                    if for_sp < 1 then
                        ErrorHandler( ERROR_NEXT, nil )
                    end
                    variable[forstack[for_sp]["name"]] =
                        variable[forstack[for_sp]["name"]] +
                        forstack[for_sp]["step"]
                    if forstack[for_sp]["step"] > 0 then
                        if variable[forstack[for_sp]["name"]] > forstack[for_sp]["endvalue"] then
                            -- ループ終了
                            for_sp = for_sp - 1
                            return
                        end
                    else
                        if variable[forstack[for_sp]["name"]] < forstack[for_sp]["endvalue"] then
                            -- ループ終了
                            for_sp = for_sp - 1
                            return
                        end
                    end
                    textpointer = forstack[for_sp]["top"]
                  end;

        GOTO    = function()    
                    if textlabel[wordmemory[textpointer]..":"] == nil then
                        ErrorHandler( ERROR_LABEL, wordmemory[textpointer] )
                    else
                        textpointer = textlabel[wordmemory[textpointer]..":"]
                    end
                  end;
        
        GOSUB   = function()
                    if textlabel[wordmemory[textpointer]..":"] == nil then
                        ErrorHandler( ERROR_LABEL, wordmemory[textpointer] )
                    else
                        gosub_sp = gosub_sp + 1
                        gosubstack[gosub_sp] = textpointer + 1;
                        textpointer = textlabel[wordmemory[textpointer]..":"]
                    end
                  end;
        
        RETURN  = function()
                    if gosubstack[gosub_sp] == nil then
                        ErrorHandler( ERROR_RETURN, nil )
                    else
                        textpointer = gosubstack[gosub_sp]
                        gosub_sp = gosub_sp - 1
                    end
                  end;
                  
        END     = function()
                    print( "\nEND" )
                    os.exit(0)     
                  end;
        
        PRINT   = function()
                    local sTmp
                    textpointer = textpointer - 1
                    repeat
                        textpointer = textpointer + 1
                        sTmp = string.match(wordmemory[textpointer],'^%"(.*)%"$')
                        if sTmp ~= nil then
                            io.write( sTmp )
                            textpointer = textpointer + 1
                        else
                            io.write( Expression() )
                        end
                    until wordmemory[textpointer] ~= ","
                  end;
                  
        LFCR    = function()
                    print("")
                  end;
}

basic_function = {
        ABS =   function()  return math.abs(Expression(")"))    end;
        SQRT =  function()  return math.sqrt(Expression(")"))   end;
        CEIL =  function()  return math.ceil(Expression(")"))   end;
        FLOOR = function()  return math.floor(Expression(")"))  end;
                
        SGN =   function()
                    local n
                    n = Expression(")")
                    if n > 0 then
                        n = 1
                    elseif n < 0 then
                        n = -1
                    else
                        n = 0
                    end
                    return n
                end;
}

--

--
--  数式処理
--
function Expression( endchr )

    local function factor()
        -- 項（符号・関数その他)
        local n, op
        op = wordmemory[textpointer]
        if op == "+" then
            textpointer = textpointer + 1
            n = factor()
        elseif op == "-" then
            textpointer = textpointer + 1
            n = -factor()
        elseif op == "!" then
            textpointer = textpointer + 1
            n = not factor()
        elseif op == "(" then
            textpointer = textpointer + 1
            n = Expression( ")" )
        else
            if basic_function[op] ~= nil then
                -- 組み込み関数
                textpointer = textpointer + 1
                if wordmemory[textpointer] ~= "(" then
                    ErrorHandler( ERROR_SYNTAX, nil )
                end
                textpointer = textpointer + 1
                n = basic_function[op]()
            else
                n = tonumber(op)
                if n == nil then
                    if op == string.match(op, "[%w_]+") then
                        -- 変数
                        if variable[op] == nil then
                            variable[op] = 0
                        end
                        n = variable[op]
                    else
                        ErrorHandler( ERROR_SYNTAX, wordmemory[textpointer] )
                    end
                end
                textpointer = textpointer + 1
            end
        end
        return n
    end

    local function term5()
        local n
        -- 累乗
        n = factor()
        while wordmemory[textpointer] == "^" do
            textpointer = textpointer + 1
            n = n ^ factor()
        end
        return n
    end
    
    local function term4()
        -- 乗除余
        local n, n1, op
        n = term5()
        op = wordmemory[textpointer]
        while op == "*" or op == "/" or op == "%" do
            textpointer = textpointer + 1
            n1 = term5()
            if op == "*" then
                n = n * n1
            else
                if n1 == 0 then
                    ErrorHandler(ERROR_DIV,wordmemory[textpointer])
                end
                n = op == "/" and n / n1 or n % n1
            end
            op = wordmemory[textpointer]
        end
        return n
    end

    local function term3()
        -- 加減
        local n, n1, op
        n = term4()
        op = wordmemory[textpointer]
        while op == "+" or op == "-" do
            textpointer = textpointer + 1
            n1 = term4()
            if op == "+" then
                n = n + n1
            else
                n = n - n1
            end
            op = wordmemory[textpointer]
        end
        return n
    end

    local function term2()
        -- 比較（大小）
        local n, n1, op
        n = term3()
        op = wordmemory[textpointer]
        while op == ">" or op == "<" or op == "<=" or op == ">=" do
            textpointer = textpointer + 1
            n1 = term3()
            if op == ">" then
                n = (n > n1) and 1 or 0
            elseif op == ">=" then
                n = (n >= n1) and 1 or 0
            elseif op == "<" then
                n = (n < n1) and 1 or 0
            else
                n = (n <= n1) and 1 or 0
            end
            op = wordmemory[textpointer]
        end
        return n
    end

    local function term1()
        -- 比較（等・不等）
        local n, n1, op
        n = term2()
        op = wordmemory[textpointer]
        while op == "==" or op == "<>" or op == "!=" do
            textpointer = textpointer + 1
            n1 = term2()
            if op == "==" then
                n = (n==n1) and 1 or 0
            else
                n = (n~=n1) and 1 or 0
            end
            op = wordmemory[textpointer]
        end
        return n
    end

    -- 条件式の連結
    local n, n1, op
    n = term1()
    op = wordmemory[textpointer]
    while op == "AND" or op == "OR" do
        textpointer = textpointer + 1 
        n1 = term1()
        if op == "AND" then
            n = (n ~= 0 and n1 ~= 0) and 1 or 0
        else
            n = (n ~= 0 or n1 ~= 0 ) and 1 or 0
        end
        op = wordmemory[textpointer]
    end
    if op == endchr then
        -- 正常終了
        textpointer = textpointer + 1
    elseif endchr ~= nil then
        ErrorHandler(ERROR_SYNTAX, wordmemory[textpointer])
    end
    -- テキスト終端(正常終了)
    return n
end

--
--  字句解析
--
function BreakApart(s) 
    --  字句解析下請け
    --      結果を配列へ書き出す
    local function SetWordMemory(n)
        -- ラベルの格納
        if string.sub(n,-1) == ":" then
            textlabel[n] = wordcounter
            return
        end
        -- とりあえず演算子の連結もここで行う
        if n == "=" then
            if wordmemory[wordcounter-1] ~= nil then
                if string.find("><=!", wordmemory[wordcounter-1], 0, true ) ~= nil then
                    wordmemory[wordcounter-1] = wordmemory[wordcounter-1] .. n
                    return
                end
            end
        elseif n == ">" then
            if wordmemory[wordcounter-1] ~= nil then
                if wordmemory[wordcounter-1] == "<" then
                    wordmemory[wordcounter-1] = wordmemory[wordcounter-1] .. n
                    return
                end
            end
        end
        wordmemory[wordcounter]=n
        wordcounter = wordcounter + 1
    end

    local pos, op, w, endpos, reg, i
    -- 文字列及びラベルの検出
    --  後段の処理では
    --      ・内容に空白が含まれると分断される。
    --      ・文字と区切子の連結が許されない。
    --  ので、ここで別途処理する。
    for i, reg in pairs({'()(".-")()', '()([%w_]+%:)()'}) do
        pos,w,endpos = string.match(s,reg) 
        if pos ~= nil then
            if pos > 1 then
                BreakApart(string.sub(s,1,pos-1))
            end
            SetWordMemory(w)
            if endpos <= #s then
                BreakApart(string.sub(s,endpos))
            end
            return
        end
    end
    
    -- 空白で予約語を切り出す。演算子の結合はここでは行わない。
    for pos,w,endpos in string.gmatch(s,'()(%S+)()') do 
        if w == "REM" then
            -- 以降をコメントとして無視する
            break
        end

        pos, op, endpos = string.match(w, '()([^_%w%.])()' ) 
        if pos ~= nil then
            -- 演算子・区切子を検出
            if pos > 1 then
                BreakApart(string.sub(w,1,pos-1))
            end
            SetWordMemory(op)
            if endpos <= #w then
                BreakApart(string.sub(w,endpos))
            end
        else
            -- 予約語の書き出し
            SetWordMemory(w)
        end
    end
end


--
--  Main routine
--

-- 字句解析
linenumber=0
wordcounter=1
for s in io.lines("sample.bas") do
    linenumber = linenumber + 1
    wordmemory[wordcounter] = string.format("#%d#", linenumber)
    wordcounter = wordcounter + 1
    BreakApart(s)
end

-- for x,s in pairs(wordmemory) do print( x, s ) end

-- インタープリタ本体
textpointer = 1
while textpointer < wordcounter do
    if basic_word[ wordmemory[textpointer] ] == nil then
        if wordmemory[textpointer+1] == "=" then
            basic_word["LET"]()
        else
            -- 実行中の行番号の取り出し
            linenumber = string.match(wordmemory[textpointer],"#(%d+)#")
            if linenumber ~= nil then
                textpointer = textpointer + 1
            else
                ErrorHandler( ERROR_SYNTAX, wordmemory[textpointer] )
            end
        end
    else
        textpointer = textpointer + 1
        basic_word[ wordmemory[textpointer-1] ]()
    end
end
