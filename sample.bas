REM
REM TEST FOR BASIC
REM
REM GOTO TEST

FOR X=1 TO 100
    FOR Y=X TO 100
        Z=SQRT(X^2+Y^2)
        IF FLOOR(Z)==Z THEN 
            PRINT X," ",Y," ",Z,"  ",FLOOR(Z) 
            LFCR
        ENDIF
    NEXT
NEXT

TEST:
A=1 B=2 C=3
A=B*C
PRINT 10 /3, "    ", 10 % 3
END


