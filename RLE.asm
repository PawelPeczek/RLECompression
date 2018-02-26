;---------------------------------------------------------------------------------------------------------------------------------------
;|															Czesc deklaracyjna														   |
;---------------------------------------------------------------------------------------------------------------------------------------

data1 segment
	ArgTab		db	128 dup(24h)	;	Wypełnienie tablicy argumentow pobranych z lini polecen samymi znakami "$" -  w skutek czego  
									;	nie trzeba juz dodawać na koncu ciagu tego znaku. Maksymalnie przyjmuje 127 znakow + dolar 
									;	terminujacy - tyle przyjmuje maksymalnie od adresu PSP:81h do PSP:FFh
	ArgStrLen 	db	0				;	Dlugosc ciagu znakow przekazanego do wiersza polecenia jako argument
	ArgNumber	db 	0				;	Ilosc argumentow
	ArgsLen		db	64 dup(0)		;	Tablica (maksymalnie 64 argumenty, bo gdyby przekazac arg1 arg2 ... to liczba argumentow 
									;	maksymalnie wyniesie 64 - kazdy argument po 1 znak (1B ASCII) + odstep, np spacja 20h 
									;	ASCII - 1B) - okreslenie przesuniecia wzgledem poczatku tablicy
	ArgOffsets	dw 	64 dup(offset ArgTab)	;	Tablica offsetow argumentów - dla bezpieczenstwa - ustawiam offsety na istniejacy poczatek 1. argumentu
	endl		db	10,13,"$"
	errorMsgOff	dw 	offset statusOK
	statusOK	db 	"Status: [OK!]$"
	ToFewArgs	db 	"Status: [ERROR] Podano zbyt malo argumentow!$"
	ToManyArgs		db 	"Status: [ERROR] Podano zbyt duzo argumentow!$"
	nonExiArgEx 	db 	"Status: [ERROR] Odwolanie do nieistniejacego argumentu!$"
	fileNotFoundEx 	db	"Status: [ERROR] Pliku nie odnaleziono lub brak praw dostepu!$"
	invalidPathEx 	db 	"Status: [ERROR] Bledna sciezka do pliku!$"
	accDeniedEx	  	db 	"Status: [ERROR] Odmowa dostepu do pliku!$"
	toManyHandlersEx db "Status: [ERROR] Brak dostepnych uchwytow do plikow!$"
	FileExOffsets 	dw 	offset fileNotFoundEx, offset invalidPathEx, offset toManyHandlersEx, offset accDeniedEx ; Tablica offset'ow wiadomosci o bledach
	FileEx 			db 	"Status: [ERROR] Nie udalo sie wykonac operacji na pliku!$"
	closingFileEx 	db 	"Status [ERROR] Nie udalo sie zamknac lub otworzyc pliku pliku!$"
	buffEx 			db 	"Status: [ERROR] Blad podczas buforowania danych!$"
	comFilePatternEx db "Status: [ERROR] Format pliku do dekompresji nie odpowiada oczekiwanemu!$"
	errIntro 		db 	"Numer argumentu odpowiedzialnego za blad: $"
	inHandler 		dw 	? 		;	Uchwyt do pliku do oczytu danych
	outHandler 		dw 	? 		;	Uchwyt do pliku do zapisu danych
	buffer			db 	16384 dup(0) ; bufor wejsciowy - poczatkowo wypelniony zerami
	bufferOut		db 	16384 dup(0) ; bufor wyjsciowy - poczatkowo wypelniony zerami
	buffOutPointer 	dw 	0 		; Wskaznik na kolejne miejsce w buforze WYJSCIOWYM
	bufferPointer 	dw 	0 		; Wskaznik na kolejne miejsce w buforze WEJSCIOWYM
	buffLoad		dw 	0 		; Zajetosc bufora
	buffSize		dw 	16384 	; Rozmiar bufora 16KB
	typeOfErr 		db 	0 		; Typ bledu pozwala na zinterpretowanie, jakie informacje nalezy wypisac w obsludze bledu
	auxMessOff		dw 	?		; Obsluga bledow nieraz wymaga podania dodatkowych informacji - tutaj zmienna na offset
	fileCausedErr	db 	?,"$" 	; Numer argumentu, ktory wywolal blad.
data1 ends

;---------------------------------------------------------------------------------------------------------------------------------------
;|													   Czesc deklaracyjna - KONIEC													   |
;---------------------------------------------------------------------------------------------------------------------------------------


;---------------------------------------------------------------------------------------------------------------------------------------
;|																SEGMENT KODU														   |
;---------------------------------------------------------------------------------------------------------------------------------------

code1 segment
	assume CS:code1, DS:data1, SS:stack1 		;	INFORMUJE kompilator do ktorego rej. ma sie odwolywac gdy napotka podana etykiete
	.286										;	Dla ułatwienia - pusha/popa dzieki czemu jedno polecenie odklada/zdejmuje wszystkie 
												;	rejestry na/ze stos/-u
	
	start:

			;	Inicjalizacja stosu
			mov AX, seg stack1
			mov SS, AX
			mov SP, offset top
			;	Koniec inicjalizacji

			; Inicjalizacja DS, aby wskazywal na segment data1
			mov AX, seg data1
			mov DS, AX
			

			;--------------------------------------------------------------------------------
			;	Punkt wejscia
			;--------------------------------------------------------------------------------
			
			main:
			call ParseArguments ; Funkcja dokonuje parsowania argumentow
			cmp ArgNumber, 2d 	; Sprawdzenie ilosci argumentow
			jb FewArgsEx		; Jesli mniej niz 2 argumenty
			cmp ArgNumber, 3d
			jg ManyArgsEx 		; jesli wiecej niz 3 argumenty
			
			; Weryfikacja pierszego argumentu celem okreslenia czy -d czy nazwa pliku (i odpowiednio dekompresja lub kompresja)
			mov AL, 1d 	; Konwencja wywolania procedury GetArg wymaga podania w AL numer argumentu ktory chcemy
			call GetArg
			mov SI, AX 	;	Po wywolaniu w AX mamy offset argumentu, przenosze go do SI
			cmp [SI], byte ptr "-" ; Sprawdzanie czy pod offsetem znajduje sie kod ASCII "-"
			jne Comp 	;	Jesli nie to wykonujemy kompresje
			inc SI 		; Przesuniecie na kolejny znak
			cmp [SI], byte ptr "d" ; Sprawdzanie czy pod offsetem znajduje sie kod ASCII "-"
			jne Comp 	;	Jesli nie to wykonujemy kompresje
			mov SI, offset ArgsLen ; Tablica ArgsLen zawiera dlugosci wszystkich argumentow - sprawdzamy jaka dlugosc ma pierwszy argument
			cmp [SI], byte ptr 3d  ; Jezeli nie jest to dlugosc 3 (dlugosc liczymy wraz ze znakiem terminujacym argument) to chodzi nam o kompresje
			jne Comp
			Decomp:
				call Decompression
				jmp Exit
			Comp:
				call Compression
			Exit:
				call Terminate

			; Obslugi bledow
			FewArgsEx:
				mov errorMsgOff, offset ToFewArgs
				jmp Exit

			ManyArgsEx:
				mov errorMsgOff, offset ToManyArgs
				jmp Exit
		
			;--------------------------------------------------------------------------------
			;	KONIEC WYKONANIA
			;--------------------------------------------------------------------------------

	
	;----------------------------------------------------------------------------------------------------------------
	;
	;	Procedura ParseArguments
	;	Wykonuje parsowanie argumentow
	; 	Sparsowane argumenty umieszcza w tablicy ArgTab, ArgsLen, ArgOffsets
	;	IN: 	none
	;	OUT: 	none
	;	DESC:	Procedura wlasciwa sparsowania argumentow. Najpierw zabezpieczane sa wartosci rejestrow. Nastepnie 
	;			wywolywana jest funkcja 51h przerwania 21h, ktora powoduje zaladowanie do BX segmentu PSP. wartosc
	;			jest kopiowana do rejestru segmentowego ES. Nastepnie pobierana jest do AL dlugosc przekazanych
	;			(wraz z poczatkowa spacja) z adresu PSP:[80h]. Jezeli nie podano zadnych argumentow - Wywolanie
	;			procedury Terminate. Nastepnie ustawiana jest wlasciwa dlugosc parametrow w pamieci (ArgStrLen)
	;			i ustawiony zostaje licznik petli na ta dlugosc. Rejestr indeksowy SI bedzie odpowiadal za wskazanie
	;			kolejnego znaku PSP:SI od wartosci SI 82h - pominiecie spacji. DI - wskaze miejsce do kopiowania
	;			DS:SI, gdzie DS to tak naprawde segment ArgTab. Przy okazji DS:BX bedzie wskazywac kolejne komorki
	;			tablicy ArgsLen - gdzie beda dlugosci poszczegolnych argumentow. W petli reading przechodzimy po
	;			wzsystkich znakach - wywolujac na kazdym procedure HandleCharacter. Po zakonzeniu petli musimy
	; 			wstawic znak terminujacy $ na koncu ostatniego argumentu i okreslic prawidlowo jego dlugosc.
	; 
	;----------------------------------------------------------------------------------------------------------------


	ParseArguments proc
		
		pusha
		mov AH, 51h
		int 21h						;	Wywolanie przerwania celem ustalenia PSP w BX
		mov AX, BX
		mov ES, AX 					;	Unikam przekazania nie z AX do rejestru segmentowego	
		mov AL, byte ptr ES:[80h]	;	DO AL ilosc znakow przekazanych w argumentach 
		cmp AL, 1 					;	Sprawdzam czy ze spacja jest <= 1 znak - jesli tak to nie ma argumentow
		jbe NoArgs					;	Brak argumentow
		; else 
		dec AL 						;	Pomijanie spacji ES:[81h] -> 1B 
		mov ArgStrLen, AL 			;	Do zmiennej dlugosc argumentow	 

		xor CX, CX
		mov CL, AL					;	Ustawienie licznika petli
		
		mov SI, 82h					;	Poczatek ciagu argumentow - pomijam spacje ES:[81h] -> 1B 
		mov DI, offset ArgTab		;	DI bedzie adresowac przesuniecia offsetu tavlicy
		xor AX, AX 					;	Przyjmuje nastepujaca konwencje AL -> aktualny znak
									;	AH -> ilosc znakow argumentu (zaakceptowanych)
		mov BX, offset ArgsLen
		mov DX, offset ArgOffsets	
		reading:					;	Petla wczytujaca kolejne znaki
			mov AL, ES:[SI]
			call HandleCharacter
			inc SI
		loop reading
		
		mov [DI], byte ptr 0 		; 	Upewnienie sie co do znaku 0 na koncu - wymagane przy obsludze pliku!!!
		inc AH 						; 	Zwiekszenie dlugosci
		mov [BX], AH 				;	Przypisanie dlugosci do zakanczanego argumentu

		finSt:
			popa
			ret

		NoArgs:
			mov ArgNumber, 0d
			jmp finSt

	ParseArguments endp

	;-------------------------------------------------------------------------------------------------------------
	;	Koniec procedury ParseArguments
	;-------------------------------------------------------------------------------------------------------------

	
	;-------------------------------------------------------------------------------------------------------------
	;
	;	Procedura Terminate
	;	Konczy program
	; 	IN: none
	;	OUT: none
	;
	;-------------------------------------------------------------------------------------------------------------


	Terminate proc
		
		cmp typeOfErr, 2d ; Sprawdzenie typu bledu 0 - standard, 1, lub 2
		je FirstType

		cmp typeOfErr, 1d
		je FirstType

		jmp standard

		FirstType:
			mov AX, seg errIntro ; Wypisanie tekstu wprowadzajacego do obslugi bledu
			mov DS, AX
			mov DX, offset errIntro
			mov AH, 9
			int 21h
			
			add fileCausedErr, "0" ; Zeby dostac kod ASCII znaku "1", "2" lub "3"
			mov DX, offset fileCausedErr ; Wypisanie numeru argumentu odpowiadajacego za blad
			mov AH, 9
			int 21h
			mov DX, offset endl
			mov AH, 9
			int 21h
			jmp standard

		SecondType: ; Wypisanie dodatkowej informacji dot. obslugi bledu
			mov AX, seg auxMessOff
			mov DS, AX
			mov DX, auxMessOff
			mov AH, 9
			int 21h

		standard:
			mov AX, seg errorMsgOff ; Wypisanie statusu wykonania
			mov DS, AX
			mov DX, errorMsgOff
			mov AH, 9
			int 21h

		retToOS:
			mov AH, 4CH
			int 21h
		
	Terminate endp

	;-------------------------------------------------------------------------------------------------------------
	;	Koniec procedury Terminate
	;-------------------------------------------------------------------------------------------------------------


	;-------------------------------------------------------------------------------------------------------------
	;
	;	Procedura HandleCharacter(PRIVATE)
	;	Konczy program
	; 	BIDIRECT: 	AL -> znak, AH -> ilosc znakow argumentu (ktore juz posiada)
	;				DI -> offset do zapisania kolejnego znaku
	;				SI -> Czytany offset
	;				BX -> przesuniecie wzgledem tablicy ArgsLen
	;				DX -> przesuniecie wzgledem tablicy ArgOffsets
	;	OUT: 		modyfikacja podanych wyzej rejestow
	;	DESC:		Procedura sprawdza najpierw czy AL (znak) ma kod ASCII znaku CR, lub LF. Wowczas przechodzi 
	;				do etykiety CRLEEncounter.
	;				CRLEEncounter:
	;					Jesli ilosc znakow w przetwarzanym argumencie jest rozna niz zero - nalezy zakonczyc 
	;					ten argument - skok do CloseArgument
	;					W przwciwnym razie skok do HandleCharacterFinalizer - wyjscie z procedury
	;				Jezeli nie bylo skoku to sprawdzane jest czy znak to inny znak niedrukowalny 
	;				(kod ASCII <= 20h). Jezei tak to skok do OtherWhiteCharEncounter
	;				OtherWhiteCharEncounter:
	;					Jesli ilosc znakow w przetwarzanym argumencie jest rozna niz zero - wystepuje bialy znak
	;					po argumencie i tzrreba skoczyc do CloseArgument, w przeciwnym razie wychodzimy - nic nie
	;					robiac (w glownej petli oczywiscie zmienia sie SI - ktore wskazuje na znak do badania)
	;				Jeżeli to jednak nie byl bialy znak sprawdzane jest czy jest to pierwszy czy kolejny znak
	;				argumentu. Pierwszy -> skok do OpenNewArg
	;				OpenNewArg:
	;					Zwiekszenie liczby argumentow i skok do AddCharToArg
	;				AddCharToArg:
	;					Obsluga dodawania znaku do listy argumentow. Do DS:[DI] - kolejny bajt w tablicy ArgTab
	;					dopisywany jest dany znak. DI jest przestawiany na kolejny bajt, zwiekszana jest liczba
	;					znakow argumentu. Potem nastepuje wyjscie.
	;				CloseArgument:
	;					Zwiekszenie AH ($ na koncu tez zajmuje miejsce) i wpisanie liczby do DS:[BX] - czyli 
	;					kolejnej komorki ArgsLen. BX jest przestawiany o bajt do przpodu, AH jest zerowane,
	;					do DS:[DI] wpisany jest znak terminujacy argument ($), przestawiany jest [DI] na kolejny
	;					bajt i wychodzimy.
	;				HandleCharacterFinalizer:
	;					Powrot do caller'a.   
	;
	;-------------------------------------------------------------------------------------------------------------


	HandleCharacter proc
		
		; Nie modyfikuje rejestrow nieswiadmie - nie odkladam nic na stos

		
		cmp AL, 0Dh
		je CRLEEncounter 						; Napotkano CR
		cmp AL, 0Ah
		je CRLEEncounter						; Napotkano LF
		cmp AL, 20h
		jbe OtherWhiteCharEncounter 			;	AL <= 20h - napotkano bialy znak (inny niz CR LF)
		;	czyli jeednak napotkano znak drukowany
		
		cmp AH, 0d 								;	Znaleziono znak otwierajacy nowy argument
		je OpenNewArg
		jmp AddCharToArg						; 	else - Dodanie znaku do istniejaceg argumentu

		CRLEEncounter:
			cmp AH, 0d
			jne CloseArgument					;	AH != 0 -> bialy znak PO argumencie
			jmp HandleCharacterFinalizer
		
		OtherWhiteCharEncounter:
			cmp AH, 0d
			jne CloseArgument					;	AH != 0 -> bialy znak PO argumencie
			jmp HandleCharacterFinalizer

		OpenNewArg:
			inc ArgNumber
			push SI
			mov SI, DX
			mov [SI], word ptr DI
			pop SI
			jmp AddCharToArg

		AddCharToArg:
			mov [DI], AL
			inc DI
			inc AH
			jmp HandleCharacterFinalizer

		CloseArgument:
			inc AH
			mov [BX], AH 						;	Przypisanie dlugosci do zakanczanego argumentu
			inc BX
			xor AH, AH 							; 	Zerowanie ilosci znakow argumentu
			mov [DI], byte ptr 0						;	Wpisanie 0 na koncu argumentu - wymagane do poprawnej obslugi pliku
			inc DI	
			inc DX								; Zwiększenie offsetu tablicy ArgOffsets o 2 - bo przechowuje word'y
			inc DX
			jmp HandleCharacterFinalizer

		HandleCharacterFinalizer:
			ret
		
	HandleCharacter endp

	;-------------------------------------------------------------------------------------------------------------
	;	Koniec procedury HandleCharacter
	;-------------------------------------------------------------------------------------------------------------


	;-------------------------------------------------------------------------------------------------------------
	;	
	;	Procedura GetArg
	;	Wypisuje argumenty
	; 	IN: 	REGISTERS: 	AL -> numer argumentu do pobrania
	;			MEMORY:		ArgNumber, ArgTab, ArgsLen
	;	OUT: 	AX -> offset argumentu
	;	DESC:	Procedura zwraca w AX offset odpowiedniego argumentu. Najpierw zabezpieczana jest wartosc 
	;			rejestrow, nastepnie sprawdzamy, czy nie odwolujemy sie do argumentu poza zakresem - jesli tak
	;			-> wywolanie obslugi bledu. nastepnie CL jako licznik jest ustawiany na o jeden mniej niz numer
	;			argumentu. Do bazwoego offsetu dodajemy dlugosci wszystkich poprzedzajacych go argumentow w petli 
	;			while (etykieta testif)
	;			
	;-------------------------------------------------------------------------------------------------------------


	GetArg proc
		
		push CX						;	Odlozenie na stos rejestrow ktore beda wykorzystane
		push BX
		push DX
		push SI

		XOR CX, CX					;	Wyzerowanie CX

		cmp AL, ArgNumber			; 	Jesli proba odwolania sie do nieistniej. argumentu - wyjatek
		ja ErrHandling 				;	AL > ArgNumber
		; else
		dec AL
		sal AL, 1 	; Mnozenie razy 2 - najstarszy bit zostawiany jak jest
		
		mov SI, offset ArgOffsets ; W tym momencie wykonanie procedury to O(1)
		xor AH, AH
		add SI, AX
		mov AX, [SI]

		pop SI
		pop DX 						;	Przywrocenie wartosci rejestrow ze stosu
		pop BX
		pop CX 						
		
		ret
		
		;	Obsluga bledu
		ErrHandling:
			pop DX 						;	Przywrocenie wartosci rejestrow ze stosu
			pop BX
			pop CX 	
			push AX
			mov AX, offset nonExiArgEx
			mov errorMsgOff, AX
			pop AX
			call Terminate		

	GetArg endp

	;-------------------------------------------------------------------------------------------------------------
	;	Koniec procedury GetArg
	;-------------------------------------------------------------------------------------------------------------

	;-------------------------------------------------------------------------------------------------------------
	;
	;	Procedura Compression
	;	Wykonuje kompresje pliku wejsciowego do wyjsciowego
	; 	IN: nazwy plikow wejsciowego i wyjsciowego
	;	OUT: none
	;
	;-------------------------------------------------------------------------------------------------------------


	Compression proc
		
		push BX ; zabezpieczenie wszytskich uzytych rejestrow
		push CX
		push DX
		push SI
		push DI
		pushf

		mov AL, 1h ; konwencja wywolania GetArg
		mov BL, AL ; Zapamietuje numer arg na wypadek bledu
		call GetArg ; teraz w AX mam offset do nazwy 1. argumentu
		call OpenFile ; otwarcie pliku wejsciowego
		jc errFileOne ; jesli CF (wewnetrzne procedury zwracaja blad do gory) -> przy tym bledzie nie trzeba niczego zamykac
		mov SI, AX 	; SI bedzie przechowywac inHandler w calym przebiegu Compression i wszystkich podprocedurach

		mov AL, 2h ; pobranie 2. argumentu
		mov BL, AL ; Zapamietuje numer arg na wypadek bledu
		call GetArg ; teraz w AX mam offset do nazwy 2. argumentu

		call CreateFile ; stworzenie pliku wyjsciowego
		jc errFile ; jesli CF -> blad nalezy zamknac otwarty wczesniej plik wejsciowy
		mov DI, AX ; DI bedzie przechowywac outHandler w calym przebiegu Compression i wszystkich podprocedurach

		mov AH, 1d ;	AH -> flaga EOF: jeśli 0 to koniec pliku


		; Konwencja -> Sprawdzam czy wczesniej byl taki sam znak, jednoczesnie CX zlicza a znak 0x00 stanowi escape char
		; trzeba go zdublowac po natrafieniu
		; Pierwsze pobranie przed petla wlasciwa zeby moc latwiej sprawdzac czy ten sam znak
		xor CX, CX ; zerowanie licznika
		call GetChar ; pobranie 1. znaku
		jc err ; sprawdzenie bledu (zamknac trzeba teraz oba pliki)
		cmp AH, 0d ; sprawdzenie czy nie EOF
		je AfterEOF
		inc CX ; Pobrany wlasnie znak wystapil 1. raz Jesli od razu EOF nie wejdziemy do while
		mov BL, AL ; w BL pamietam POPRZEDNI ZNAK
		doWhile:
			call GetChar ; pobieranie kolejnego znaki
			jc err ; sprawdzenie czy nie blad
			cmp AH, 0d ; sprawdzenie czy nie EOF
			je AfterEOF
			cmp AL, 0h ; 0h (0x00) -> znak ucieczki
			jne NotEscapeCharEncounter
				; else -> obsluga znaku ucieczki
				call SaveBulk ; Zapis znakow ktore byly wczesniej
				xor CX, CX 	; 	nie ma znaczenia jaka ilosc znaku 0x00 wpisze -> i tak kolejne wystapienie bedzie obsluzone w ten sam sposob
							;	a ewentualny nowy inny znak obsluzy sie poprawnie -> SaveBulk ma na poczatku sprawdzenie czy nie dostal
							;	znaku ucieczki wiec od razu bedzie ret, a CX ustawi sie na 1 (bo napotkano nowy znak)
				call PutChar	; 2 razy umieszam AL, ktore ma 0x00, w pliku wyjsciowym
				jc err ; sprawdzenie bledu
				call PutChar ; zdublowanie znaku 0x00
				jc err ; sprawdzenie bledu
				jmp pushNewChar
			NotEscapeCharEncounter: ; jesli nie znak ucieczki
			cmp BL, AL ; sprawdzanie z poprzednim
			jne diffrentChars
			
			sameChars: ; jesli takie same znaki
				inc CX ; zwiekszamy licznik
				cmp CX, 256 ; sprawdzamy czy nie przekroczylismy ilosci, po ktorej trzebaby zapisac (ze wzgledu na ograniczenie 255)
				jne pushNewChar
				dec CX ; w tym miejscu musimy przez to ograniczenie wymusic zapis. CX po dec bedzie mialo 255
				call SaveBulk ; zapisujemy 0x00 0xff 0xKOD_ZNAKU
				jc err ; jesli wystapil blad
				xor CX, CX ; zerujemy CX
				inc CX ; CX ustawiony na 1 wszak zarejestrowalismy przekroczenie o 1
				jmp pushNewChar

			diffrentChars:
				; Trzeba najpierw zapisac odpowiednio poprzedni znak / znaki
				call SaveBulk
				jc err ; jesli wystapil blad
				xor CX, CX ; zerowanie licznika
				inc CX ; Znaki sie roznily wiec teraz mamy pojdeyncze wystapienie nowego znaku
			pushNewChar:
				mov BL, AL ; zapamietanie w BL znaku do nastepnego porownania
		jmp doWhile ; z petli wyskakujemy w przypadku bledu lub EOF

		AfterEOF: ; zapisanie koncowki do pliku
			; zapisanie w buforze ostatniego skompresowanego znaku
			call SaveBulk
			jc err ; jesli wystapil blad
			; jezeli bufor wyjsciowy nie jest pusty, nalezy wymusic zapis
			cmp bufferPointer, 0d
			je dispose ; skok do zamykania plikow
			mov AH, 40h ; wymuszenie zapisu ostatniej partii zakodowanego pliku wyjsciowego
			mov BX, DI
			mov CX, buffOutPointer
			mov DX, offset bufferOut

			int 21h

			jc err ; sprawdzenie bledu
			jmp dispose
			
	
		err:
			mov errorMsgOff, offset buffEx
			jmp dispose

		errFileOne:
			mov fileCausedErr, BL ; obsluga bledu (nie trzeba nbic zamykac)
			jmp fin

		errFile:
			mov fileCausedErr, BL ; obsluga bledu (trzeba zamknac tylko plik wejsciowy)
			jmp disposeS

		dispose: ; trzeba zamknac oba pliki
			mov AX, DI
			call DisposeFile
		
		disposeS:	
			mov AX, SI
			call DisposeFile

		fin:
			popf
			pop DI
			pop SI
			pop DX
			pop CX
			pop BX
			ret

	Compression endp

	;-------------------------------------------------------------------------------------------------------------
	;	Koniec procedury Compression
	;-------------------------------------------------------------------------------------------------------------


	;-------------------------------------------------------------------------------------------------------------
	;
	;	Procedura Decompression
	;	Wykonuje dekompresje pliku wejsciowego do wyjsciowego
	; 	IN: nazwy plikow wejsciowego i wyjsciowego
	;	OUT: none
	;
	;-------------------------------------------------------------------------------------------------------------


	Decompression proc
		
		push BX ; zabezpieczenie wszystkich wykorzystywanych rejestrow
		push CX
		push DX
		push SI
		push DI
		pushf

		mov AL, 2h ; Pobranie 2. argumentu (konwencja wywolania GetArg)
		mov BL, AL ; Zapamietuje numer na wypadek bledu
		call GetArg ; potem w AX offset do napisu 
		call OpenFile ; otwarcie pliku wejsciowego (skompresowanego)
		jc errFileOne ; blad -> nie trzeba niczego zamykac
		mov SI, AX 	; SI bedzie przechowywac inHandler w calym przebiegu Compression

		mov AL, 3h ; pobranie 3. argumentu (konwencja wywolania GetArg)
		mov BL, AL ; Zapamietuje numer na wypadek bledu
		call GetArg ; potem w AX offset do napisu 
		call CreateFile ; stworzenie pliku wyjsciowego lub wyzerowanie go
		jc errFile ; jesli blad trzeba zamknac 1. plik
		mov DI, AX ; DI bedzie przechowywac outHandler w calym przebiegu Compression

		mov AH, 1d ;	AH -> flaga EOF: jeśli 0 to koniec pliku

		decompressLoop:
			call GetChar ; pobranie pierwszego znaku
			jc err ; jesli blad
			cmp AH, 0d ; sprawdzenie czy nie EOF -> w tym miejscu EOF jest OK
			je afterEOF
			cmp AL, 0d ; sprawdzenie czy pobrany znak to 0x00
			jne singleChar ; jesli nie to mamy zwykly znak (od razu po zapisie na poczatek petli)
			call GetChar ; sprawdzamy 2. znak
			jc err ; jesli blad
			cmp AH, 0d ; EOF w niedozwolonym miejscu!
			je compressedFilePatternEx
			cmp AL, 0d ; jesli drugi 0x00 to znaczy ze mamy odkodowac go na pojedynczy 0x00
			je escapeCharToDecompress
			xor CX, CX ; zeruje licznik CX
			mov CL, AL ; jesli dotarl tutaj to znaczy ze za drugim pobraniem odczytalismy ilosc powtorzen
			call GetChar ; pobranie 3. znaku
			jc err ; jesli error
			cmp AH, 0d ; EOF w niedozwolonym miejscu! mamy blad w pliku zakodowanym
			je compressedFilePatternEx ; Nie trzeba wykrywac 0x00 0x00 0x00 bo wylapie to escapeCharToDecompress
			call DecBulkSave ; Zapiszemy poprawnie do odkodowanej formy 0x00 0xILOSC 0xZNAK 
			jc err ; jesli blad
			jmp moveForward
			escapeCharToDecompress:
				mov AL, 0d ; wpisuje do pliku wyjsciowego raz znak ecieczki 0x00
				call PutChar
				jc err ; jesli blad
				jmp moveForward
			singleChar:	;	jesli jest to pojedynczy, nie skompresowany znak
				call PutChar ; zapisujemy pojedynczy znak
				jc err ; jelsi blad
		moveForward:
		jmp decompressLoop

		afterEOF:
			
			cmp buffOutPointer, 0d ; sprawdzamy czy bufor wyjsciowy jest pusty
			je dispose
			mov AH, 40h ; jesli nie to wymuszam zapisanie wg konwencji funkcji 40h przerwania 21h
			mov BX, DI
			mov CX, buffOutPointer
			mov DX, offset bufferOut

			int 21h

			jc err ; jesli blad
			jmp dispose ; zamykamy oba pliki


		compressedFilePatternEx:
			mov AX, DI ; w AX teraz handler pliku wyjsciowego
			call DisposeFile ; trzeba zamknac plik wyjsciowy
			mov AL, 3d ; pobranie nazwy pliku wyjsciowego
			call GetArg 
			mov BX, AX ; przekazanie do BX offsetu nazwy
			call DeleteFile ; skoro plik wejsciowy nie byl poprawny -> wyjsciowy zawiera smieci i trzeba go usunac
			jc errDelFil ; wykrycie bledu przy usuwaniu
			mov errorMsgOff, offset comFilePatternEx ; odpowiedni komunikat bledu
			jmp disposeS ; skok do zamkniecia zrodla
			errDelFil: ; obsluga bledu
				mov typeOfErr, 2d
				mov auxMessOff, offset comFilePatternEx ; wpisanie dodatkowego komunikatu o bledzie
				call SetErrMsg ; ustawienie komunikatow
				jmp disposeS ; skok do 

		err:
			mov errorMsgOff, offset buffEx
			jmp dispose ; skok do zamkniecia obu plikow

		errFileOne:
			mov fileCausedErr, BL ; jesli pierwszy spowoduje blad to nic nie jest jeszcze otwarte
			jmp fin

		errFile:
			mov fileCausedErr, BL
		
		dispose:
			mov AX, DI
			call DisposeFile

		disposeS:
			mov AX, SI
			call DisposeFile

		fin:
			popf
			pop DI
			pop SI
			pop DX
			pop CX
			pop BX
			ret

	Decompression endp

	;-------------------------------------------------------------------------------------------------------------
	;	Koniec procedury Decompression
	;-------------------------------------------------------------------------------------------------------------

	;-------------------------------------------------------------------------------------------------------------
	;
	;	Procedura SaveBulk
	;	Zapisuje blokowo dane do bufora przy kompresji 
	; 	IN: 	CX -> ilosc powtorzen znaku
	;			BL -> znak
	;			DI -> handler pliku do zapisu
	;	OUT: 	CF -> jesli blad
	;
	;-------------------------------------------------------------------------------------------------------------


	SaveBulk proc

		cmp BL, 0h ; sprawdzenie czy nie ma do zapisu znaku o kodzie ASCII 0 wtedy po prostu wyjsc z procedury
		je fin
		push AX ; zabezpieczam AX, bo tam wynik wywolania GetChar, w ktorym jest juz inny znak
		cmp CL, 3d ; sprawdzam czy ilosc powtorzen wieksza czy mniejsza niz 3 -> moge sprawdzac CL bo ilosc powtorzen do 255
		jbe normalPut ; jesli CL <= 3 wstawiam po prostu odpowiednia ilosc razy znak z BL do pliku
			mov AL, 0h ; jesli nie wykonujemy kompresje 0x00 jako pierwsze do pliku
			call PutChar
			jc fin ; sprawdzenie bledu w CF
			mov AL, CL 	; Wartosc w CX bedzie z przedzialu 0-255, nie byl uzyty tylko CL, zeby nie trzeba bylo przy kazdej
						; petli wykrywac przeniesienia operacji inc CL
			call PutChar ; wpisanie ilosci powtorzen do pliku
			jc fin ; sprawdzenie bledu
			mov AL, BL ; wpisanie wlasciwego znaku
			call PutChar
			jc fin
			jmp afterNormalPut
		normalPut: ; wstawianie w petli odpowiedniej ilosci znakow (1, 2 lub 3) do pliku
			mov AL, BL
			insertLoop:
				call PutChar
				jc fin
			loop insertLoop
		afterNormalPut:
			pop AX ; przywrocenie wartosci AX
		fin:
			ret

	SaveBulk endp

	;-------------------------------------------------------------------------------------------------------------
	;	Koniec procedury SaveBulk
	;-------------------------------------------------------------------------------------------------------------


	;-------------------------------------------------------------------------------------------------------------
	;
	;	Procedura DecBulkSave
	;	Procedura wykonywana przy dekompresji -> odpowiednia ilosc razy zapisuje w pliku wyjsciowym (przez bufor)
	;	zdekodowany znak
	; 	IN: 	CX -> ilosc powtorzen znaku (w zasadzie zawsze bedzie uzyty tylko CL)
	;			AL -> znak
	;			DI -> handler pliku do zapisu
	;	OUT:	CF -> jesli blad
	;
	;-------------------------------------------------------------------------------------------------------------


	DecBulkSave proc

		blkSave:
			call PutChar
			jc fin ; Jesli Blad (CF ustawione od razu wyskakujemy z procedury)
		loop blkSave ; loop w oparciu o licznik CX
		
		fin:
			ret

	DecBulkSave endp

	;-------------------------------------------------------------------------------------------------------------
	;	Koniec procedury DecBulkSave
	;-------------------------------------------------------------------------------------------------------------

	;-------------------------------------------------------------------------------------------------------------
	;
	;	Procedura OpenFile
	;	Otwiera plik do odczytu
	;	Zgodnie z kowencja wywolania funkcji 3Dh przerwania 21h jako argument podano offset do poczatku
	;	ciagu znakow terminowanego znakiem 0 -> ktory reprezentuje nazwe pliku. Tryb otwarcia ustawiono na 0 (do
	;	odczytu)
	; 	IN: 	AX -> offset poczatku nazwy pliku
	;			opcje (tryb otwarcia) 0 - read (TA OPCJA JEST UZYTA); 1 - write; 2 - both;
	;	OUT: 	CF -> jesli ustawiona blad
	;			AX -> uchwyt jesli OK, w przypadku bledu -> jego kod
	;
	;-------------------------------------------------------------------------------------------------------------


	OpenFile proc

		push DX
		
		mov DX, AX ; Konwencja wywolania funkcji otwarcia pliku wymaga aby offset do nazwy znajdowal sie w DX
		mov AL, 0d ; W AL - tryb otwarcia pliku
		mov AH, 3Dh ; W AH - numer funkcji przerwania ktora chcemy wywolac
		int 21h ; Wywolanie przerwania 
		jc ErrorOpeningFile ; Sprawdzenie flagi CF (bylaby ustawiona w przypadku bledus)
		jmp fin ; Skok do wyjscia jesli nie wykryto  bledu
		
		ErrorOpeningFile:
			call SetErrMsg ; Wywolanie procedury, ktora ustawia odpowiednie komunikaty o bledach
			
		fin:

			pop DX
			ret
		
	OpenFile endp

	;-------------------------------------------------------------------------------------------------------------
	;	Koniec procedury OpenFile
	;-------------------------------------------------------------------------------------------------------------



	;-------------------------------------------------------------------------------------------------------------
	;	Procedura DeleteFile
	;	IN:		AX -> offset poczatku nazwy pliku (ciag znakow terminowany 0)
	;	OUT:	CF -> jesli ustawione blad
	;			AX -> ew kod bledu
	;-------------------------------------------------------------------------------------------------------------

	DeleteFile proc
		
		push DX
		mov DX, AX
		mov AH, 41h
		int 21h
		pop DX
		ret

	DeleteFile endp

	;-------------------------------------------------------------------------------------------------------------
	;	Koniec procedury DeleteFile
	;-------------------------------------------------------------------------------------------------------------

	;-------------------------------------------------------------------------------------------------------------
	;	Procedura SetErrMsg
	;	IN:		AX -> kod bledu (wywolana tylko w przypadku kiedy flaga CF jest ustawiona po wykonaniu przerwania)
	;	OUT:	errorMsgOff -> offset odpowiedniego komunikatu bledu
	;			typeOfErr -> typ bledu - pozwoli na poprawne wypisanie komunikatu
	;-------------------------------------------------------------------------------------------------------------

	SetErrMsg proc
		
		pushf ; Odlozenie na stos rejestru flagowego ze wzgledu na to ze chcemy aby ustawiona flaga CF nie zostala naruszona
		mov typeOfErr, 1d ; Wymagane ze wzgledu na poprawna obsluge bledu. Kod bledu 1 oznacza ze nie mozna bylo otworzyc pliku
		cmp AL, 5h ; Porownanie majace na celu okreslenie ktory offset z tablicy nalezy przypisac -> jesli wiekszy niz 5 blad niestandardowy
		jg unknown ; kod > 05h
		
		dec AL
		dec AL ; Dostosowanie do formatu kodow bledow (ponizej tabelka)
		;---DOS 2.0+ ---
		;00h (0)   no error <- nie interesuje nas
		;01h (1)   function number invalid <- nie interesuje nas
		;02h (2)   file not found
		;03h (3)   path not found
		;04h (4)   too many open files (no handles available)
		;05h (5)   access denied
		sal AL, 1 ; offsety w tablicy FileExOffsets jako word'y dlatego chcemy pomnozyc razy dwa numer argumentu (zeby przesowac sie co 2B)
		xor AH, AH ; wyzerowanie AH
		push SI ; zabezpieczenie SI
		mov SI, offset FileExOffsets ; Do SI wprowadzony offset z tablica offsetow informacji o bledach
		add SI, AX ; wybor konkretnego offsetu
		mov SI, [SI] ; Do SI zaladowana jest zawartosc komorki pamieci DS:[SI] czyli offset odpowiedniego ciagu znakow
		mov errorMsgOff, SI ; zaladowanie informacji o bledzie
		pop SI ; przywrocenie SI
		jmp fin

		unknown:
			mov errorMsgOff, offset FileEx ; informacja o nieznanym bledzie

		fin:
			popf ; przywrocenie wartosci rejestru flagowego
			ret			

	SetErrMsg endp

	;-------------------------------------------------------------------------------------------------------------
	;	Koniec procedury DeleteFile
	;-------------------------------------------------------------------------------------------------------------

	;-------------------------------------------------------------------------------------------------------------
	;
	;	Procedura CreateFile
	;	Tworzy plik wyjsciowy.
	;	Funkcja 3Ch przerwania 21h tworzy lub w przypdaku istnienia pliku zeruje plik wyjsciowy. W przypadku powodzenia
	;	w AX laduje uchwyt do pliku z trybem zapisu i odczytu
	; 	IN: 	AX -> offset poczatku nazwy pliku - ciag znakow terminowany 0
	;			
	;	OUT: 	CF -> jesli ustawiona blad
	;			AX -> uchwyt jesli OK lub kod bledy w przypadku niepowodzenia
	;
	;-------------------------------------------------------------------------------------------------------------


	CreateFile proc
		
		push DX
		push CX
		
		mov DX, AX
		; file mode -> no write only no hidden no system no archive a wiec CX wyzerowny 
		xor CX, CX
		mov AH, 3Ch ; numer procedury 
		int 21h ; wywolanie przerwania

		jc ErrorCreatingFile ; jesli CF ustawione -> BLAD
		jmp fin
		

		ErrorCreatingFile:
			call SetErrMsg ; wywolanie procedury ustawiajacej odpowiedni komunikat bledu
			
		fin:
			pop CX
			pop DX
			ret

	CreateFile endp

	;-------------------------------------------------------------------------------------------------------------
	;	Koniec procedury CreateFile
	;-------------------------------------------------------------------------------------------------------------


	;-------------------------------------------------------------------------------------------------------------
	;
	;	Procedura DisposeFile
	;	Procedura zamyka otwarty plik. Funkcjia 3Eh przerwania 21h oczekuje w BX uchwytu pliku do zamkniecia
	; 	IN: 	AX -> handler pliku
	;			CF -> ustawione jesli blad
	;
	;-------------------------------------------------------------------------------------------------------------


	DisposeFile proc
		
		push BX

		mov BX, AX ; 3Eh potrzebuje handlera w BX
		mov AH, 3Eh ; numer funkcji przerwania
		int 21h ; wywolanie przerwania
		jc ErrClosing
		jmp fin
		ErrClosing:
			mov typeOfErr, 1d ; ustawienie odpowiedniego typu bledu
			mov errorMsgOff, offset closingFileEx ; ustawienie komunikatu
		fin:
			pop BX
			ret

	DisposeFile endp

	;-------------------------------------------------------------------------------------------------------------
	;	Koniec procedury DisposeFile
	;-------------------------------------------------------------------------------------------------------------

	;-------------------------------------------------------------------------------------------------------------
	;
	;	Procedura GetChar
	;	Pobiera jeden znak z pliku wejsciowego z wykorzystaniem bufora wejsciowego. Jesli bufor juz przetworzony ->
	; 	pobiera kolejna porcje danych z pliku wejsciowego (handler SI)
	;	IN:		bufferPointer -> wskazanie znaku ktory jest teraz do zwrocenia (o ile nie trzeba pobrac kolejnej porcji z pliku)
	;			buffLoad -> okresla ile znakow jest AKTUALNIE w buforze
	;			buffSize -> maksymalne zapelnie bufora
	;			SI -> handler do odczytywanego pliku
	; 	OUT: 	AL -> znak zwrocony z bufora
	;			AH -> jesli ustawiony na 1 to EOF
	;
	;-------------------------------------------------------------------------------------------------------------


	GetChar proc
		
		push BX ; zabezpieczenie rejestrow ktore beda uzyte
		push CX
		push DX

		mov AX, bufferPointer ; do AX znak ktory trzebaby pobrac 
		cmp AX, buffLoad ; porownanie czy nie wychodzimy poza ilosc znakow w buforze
		jne returnChar ; Jesli wartosci nie rowne (znaki liczone od 0 a ilosc bajtow od 1 wiec gdy sie zrownaja oznacza to ze czas pobrac kolejna porcje)
		mov BX, SI ; jesli nalezy pobrac kolejna porcje danych to do BX z SI przepisujemy handler pliku z ktorego czytamy
		mov CX, buffSize ; Do CX wpisac nalezy ile bajtow danych chcemy pobrac (rozmiar bufora)
		mov DX, offset buffer ; Do DX wpisujemy offset pod ktory chcemy zapisywac (jest to bufor wejsciowy)
		mov AH, 3Fh ; numer funkcji odczytywania z pliku
		int 21h ; wywolanie przerwania
		jc ErrBuffering ; jesli CF to blad
		cmp AX, 0 ; W AX dostalismy ilosc odczytanych faktycznie bajtow -> jesli 0 to znaczy EOF
		je EndOfFile
		mov buffLoad, AX ; W przeciwnym razie zapamietujemy ile w buforze
		mov bufferPointer, 0 ; ustawiamy wskaznik na poczatek bufora

		returnChar: ; zwrocenie odpowiedniego znaku w AL
			mov AH, 1d ; Przywracanie flagi EOF na false gdyz AX zostal nadpisany iloscia znakow
			push SI ; zabezpieczenie SI -> tam ma zostac na koncu handler pliku
			mov SI, offset buffer ; do SI offset bufora
			add SI, bufferPointer ; przesuniecie offsetu o odpowiednia ilosc bajtow
			mov AL, [SI] ; zaladowanie AL znakiem
			inc bufferPointer ; zwiekszenie pointera
			pop SI ; przywrocenie SI
		jmp EndOfFile ; po przejsciu przez etykiete returnChar mozna juz sie zachowywac tak samo jak EOF

		ErrBuffering:
			mov errorMsgOff, offset buffEx ; w przypadku bledu ustawiamy odpowiednia wiadomosc

		EndOfFile:
			pop DX
			pop CX
			pop BX
			; mov AH, 0d nie trzeba, poniewaz do tej etykiety skaczemy kiedy AX = 0, czyli AH tez = 0 albo w przypadku kiedy wszystko gra wtedy AH = 1
			ret

	GetChar endp

	;-------------------------------------------------------------------------------------------------------------
	;	Koniec procedury GetChar
	;-------------------------------------------------------------------------------------------------------------


	;-------------------------------------------------------------------------------------------------------------
	;
	;	Procedura PutChar
	;	Wstawia jeden znak do bufora wyjsciowego. Jesli bufor juz przepelniony -> zapisuje kolejna porcje danych 
	; 	do pliku wyjsciowego (handler DI)
	;	IN:		buffOutPointer -> wskazanie znaku ktory jest teraz do zwrocenia (o ile nie trzeba pobrac kolejnej porcji z pliku)
	;			buffSize -> maksymalne zapelnie bufora
	;			DI -> handler do zapisywanego pliku
	; 		 	AL -> znak do wpisania do bufora
	;
	;-------------------------------------------------------------------------------------------------------------


	PutChar proc

		push AX ; zabezpieczenie rejestrow
		push BX
		push CX
		push DX

		mov BX, buffOutPointer ; DO BX wpisujemy wskaznik do nastepnego pola do zapisu w buforze wyjsciowym
		cmp BX, buffSize ; jesli pointre nie jest rowny z rozmiarem bufora to znaczy ze jest jeszcze miejsce i wystarczy dopisac do bufora
		jne SaveChar
		
		push AX ; w tym momencie wiadomo ze przed zapisaniem do bufora znaki z AL nalezy zapisac na dysk porcje danych ktora byla w buforze
		mov AH, 40h ; wywolujemy funkcje 40h przerwania 21h
		mov CX, BX ; buffSize == buffOutPointer -> CX -> musi sie tam znalezc ilosc bajtow do zapisu
		mov BX, DI ; Do BX wg konwencji handler do pliku do ktorego zapisujemy
		mov DX, offset bufferOut ; do DX offset miejsca w pamieci z ktorego zapisujemy

		int 21h ; wywolanie przerwania
		pop AX ; -> still have in AL char to save in flushed buffer!
		jc errSavingBuff ; sprawdzanie CF w celu wykrycia bledu przy zapisie

		mov buffOutPointer, 0 ; po zapisaniu na dysk bufor uwazamy za pusty
		
		SaveChar: ; obsluga wpisania z AL znaku do bufora
			push SI ; zabezpieczamy SI
			mov SI, offset bufferOut ; pobieramy do SI offset bufora wyjsciowego
			add SI, buffOutPointer ; przesowamy offset na odpowiedni bajt
			mov [SI], AL ; zapisujemy zawartosc AL w DS:[SI]
			inc buffOutPointer ; zwiekszamy pointer
			pop SI ; przywracamy SI
			jmp fin

		errSavingBuff:
			mov errorMsgOff, offset buffEx ; w przypadku bledu buforowania odpowiednia informacja

		fin:
			pop DX
			pop CX
			pop BX
			pop AX
			ret

	PutChar endp

	;-------------------------------------------------------------------------------------------------------------
	;	Koniec procedury PutChar
	;-------------------------------------------------------------------------------------------------------------


code1 ends

;---------------------------------------------------------------------------------------------------------------------------------------
;|															SEGMENT KODU - KONIEC													   |
;---------------------------------------------------------------------------------------------------------------------------------------



;---------------------------------------------------------------------------------------------------------------------------------------
;|																SEGMENT STOSU														   |
;---------------------------------------------------------------------------------------------------------------------------------------

;	Deklaruje wielkosc stosu na 256 slow (512 B)
stack1 segment stack
		dw 	255 dup(?)
	top	dw 	?
stack1 ends

;---------------------------------------------------------------------------------------------------------------------------------------
;|															SEGMENT KODU - KONIEC													   |
;---------------------------------------------------------------------------------------------------------------------------------------

end start