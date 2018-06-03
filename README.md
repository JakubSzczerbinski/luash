
# Luash

Shell, w którym językiem skryptowym jest lua.

## Jak to zrobić?

Podstawą dla projektu jest interaktywny interpreter lua. Interaktywny interpreter lua działa w taki sposób, że każdy każda linia wpisana przez użytkownika jest:

- jeśli się da zinterpretować ją to lua ją wykonuje, jeśli instrukcja ma wynik to lua wypisuje jego wartość.
- jeśli nie da się zinterpretować, ale jest szansza, że po wpisaniu następnych linii będzie można zinterpretować je razem, to wczytuje następne linie i próbuje je zinterpretować.

Wprowadzę składnie, która pozwoli użytkownikowi luash tworzyć struktury danych przedstawiające polecenia.

Np.
~~~
cmd("/bin/ls") // cmd zwraca polecenie uruchamiające /bin/ls
cmd("/bin/ls")["/ -l "] // klamry pozwalają dodawać argumenty do polecenia( polecenie równoważne "/bin/ls / -l" w bashu)
cmd("/bin/ls") | cmd("/bin/grep") // polecenie ls połączone pipem z grepem
~~~

Gdy użytownik napiszę takie polecenie, lua wykonując je stworzy strukture danych opisującą je. Potem lua spróbuje wypisać jego wartość, ale przedefiniowany operator konwersji do stringa uruchomi to polecenie.

## Cele

1) Zaimplementować podstawowe wywoływanie poleceń.

2) Dodać obsługę '<', '>', |', '&&', '&' z basha.

3) Modyfikacja interpretera lua, aby przechwytywał Ctrl+C, Ctrl+Z itd.

4) Dodanie możliwości 'pluginów' dodających treści przed paskiem zachęty (np. obecny katalog, status repo gitowego, data/godzina)

5) Generowanie zmiennych, by uprościć wykonywanie poleceń z PATH. ???

6) Zmodyfikowanie interpretera lua, aby wprowadzić specjalną składnie dla poleceń ???

~~~
ls = cmd("/bin/ls")
grep = cmd("/bin/grep")
...
~~~

