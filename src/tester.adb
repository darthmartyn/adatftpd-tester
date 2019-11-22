with Ada.Command_Line;
with Ada.Direct_IO;
with Ada.Directories;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.Expect;
with GNAT.OS_Lib;
with GNAT.Random_Numbers;
with Interfaces;

--  The idea of this program is to generate a whole series of
--  binary files of various randomly selected sizes. Each byte of each
--  file is also randomly generated.
--
--  An instance of 'atftp' will then be spawned and commanded to
--  transfer each of the binary files into a local copy,  thus making
--  a pair of files.
--
--  This program will then ensure the file pairs are identical, byte by byte.
--  Any file pairs that fail this test,  are retained after the program
--  terminates and a program exit status of 1 shall be emitted.
--
--  Successful program completion shall emit a program exit status of 0.

procedure Tester is

   package Byte_IO is new Ada.Direct_IO
     (Element_Type => Interfaces.Unsigned_8);

   use Byte_IO;

   function Random_Integer is new
      GNAT.Random_Numbers.Random_Discrete (Result_Subtype => Integer);

   -- Random Number Generator for the number of files
   Number_Of_Files_Generator : GNAT.Random_Numbers.Generator;

   Program_Exit_Status : Ada.Command_Line.Exit_Status :=
     Ada.Command_Line.Success;

begin

   GNAT.Random_Numbers.Reset
     (Gen => Number_Of_Files_Generator);

   Test_TFTP_File_Transfers:
   declare

      -- Filesize generator
      File_Size_Generator : GNAT.Random_Numbers.Generator;

      Number_Of_Files : constant Positive :=
        Random_Integer
          (Gen => Number_Of_Files_Generator,
           Min => 1,
           Max => Integer(Interfaces.Unsigned_8'Last));
      --  Generate anywhere from 1 to 255 files

      subtype File_ID_Range is Integer range 1..Number_Of_Files;

      Input_Filename_Prefix : constant String := "datafilein";
      Output_Filename_Prefix : constant String := "datafileout";

      subtype Input_Filename_String is String
        (1..Input_Filename_Prefix'Length + 3);

      subtype Output_Filename_String is String
        (1..Output_Filename_Prefix'Length + 3);

      type Test_File_Data_Type is record
         Input_Filename  : Input_Filename_String;
         Output_Filename : Output_Filename_String;
         Filesize        : Integer;
         Passed          : Boolean := False;
      end record;

      type File_Array_Type is array
        (1..Number_Of_Files) of Test_File_Data_Type;

      File_Array : File_Array_Type;

   begin

      Generate_Test_Files:
      for I in File_Array'Range loop

         GNAT.Random_Numbers.Reset (Gen => File_Size_Generator);

         declare

            Trimmed_ID : constant String :=
              Ada.Strings.Fixed.Trim
                (Source => I'Img,
                 Side   => Ada.Strings.Left);

            Padded_ID : constant String :=
              (if    I <= 9 then ("00" & Trimmed_ID)
               elsif I <= 99 then ("0" & Trimmed_ID)
               else  Trimmed_ID);

         begin

            File_Array(I) :=
              (Input_Filename  => Input_Filename_Prefix & Padded_ID,
               Output_Filename => Output_Filename_Prefix & Padded_ID,
               Filesize =>
                 Random_Integer
                   (Gen => Number_Of_Files_Generator,
                    Min => 1,
                    Max => Integer(Interfaces.Unsigned_16'Last)),
               Passed => False);

            if not
               Ada.Directories.Exists (Name => File_Array(I).Input_Filename)
            then

               declare

                  File_Handle : Byte_IO.File_Type;

                  Byte_Randomizer : GNAT.Random_Numbers.Generator;

               begin

                  GNAT.Random_Numbers.Reset
                    (Gen => Byte_Randomizer);

                  Byte_IO.Create
                    (File => File_Handle,
                     Mode => Byte_IO.Out_File,
                     Name => File_Array(I).Input_Filename);

                  Byte_IO.Set_Index
                    (File => File_Handle,
                     To   => Byte_IO.Positive_Count'First);

                  For_Each_Byte_To_Write:
                  for The_Byte in 1..File_Array(I).Filesize loop

                     Write_Byte:
                     declare

                        Byte_To_Write : constant
                          Interfaces.Unsigned_8 :=
                            Interfaces.Unsigned_8
                              (Random_Integer
                                (Gen => Number_Of_Files_Generator,
                                 Min => 1,
                                 Max => Integer(Interfaces.Unsigned_8'Last)));

                     begin

                        Byte_IO.Write
                          (File => File_Handle,
                           Item => Byte_To_Write);

                     end Write_Byte;

                  end loop For_Each_Byte_To_Write;

                  Byte_IO.Close (File => File_Handle);

               end;

            end if;

         end;

      end loop Generate_Test_Files;

      For_Each_File_To_Transfer:
      for FXfer of File_Array loop

         Execute_File_Transfer:
         declare

            use GNAT.OS_Lib;

            Success : Boolean;

            Command : constant String :=
              "/usr/bin/atftp localhost --get --remote-file " &
              FXfer.Input_Filename &
              " --local-file " &
              FXfer.Output_Filename;

            Args : Argument_List_Access :=
              Argument_String_To_List (Command);

         begin

            Spawn
              (Program_Name => Args (Args'First).all,
               Args         => Args (Args'First + 1..Args'Last),
               Success      => Success);

            Free(Args);

         end Execute_File_Transfer;

      end loop For_Each_File_To_Transfer;

      -- Check the results by comparing each file
      For_Each_File_To_Check:
      for P of File_Array loop

         Check_Infile_Matches_Outfile:
         declare

            File_1_Handle : Byte_IO.File_Type;
            File_2_Handle : Byte_IO.File_Type;

            use type Ada.Directories.File_Size;

         begin

            P.Passed :=
               Ada.Directories.Exists (Name => P.Input_Filename) and then
               Ada.Directories.Exists (Name => P.Output_Filename) and then
               Ada.Directories.Size (P.Input_Filename) =
               Ada.Directories.Size (P.Output_Filename);

            if P.Passed then

               Byte_IO.Open
                 (File => File_1_Handle,
                  Mode => In_File,
                  Name => P.Input_Filename);

               Byte_IO.Reset (File => File_1_Handle);

               Byte_IO.Open
                 (File => File_2_Handle,
                  Mode => In_File,
                  Name => P.Output_Filename);

               Byte_IO.Reset (File => File_2_Handle);

               while not End_Of_File (File => File_1_Handle)
                     and then
                     not End_Of_File (File => File_2_Handle)
               loop

                  declare

                     Byte_1, Byte_2 : Interfaces.Unsigned_8;
                     use type Interfaces.Unsigned_8;

                  begin

                     Byte_IO.Read
                        (File => File_1_Handle,
                         Item => Byte_1);

                     Byte_IO.Read
                        (File => File_2_Handle,
                         Item => Byte_2);

                     P.Passed := (Byte_1 = Byte_2);

                  end;

                  exit when not P.Passed;

               end loop;

               Byte_IO.Close (File => File_1_Handle);

               Byte_IO.Close (File => File_2_Handle);

            end if;

            exit when not P.Passed;

         end Check_Infile_Matches_Outfile;

      end loop For_Each_File_To_Check;

      Delete_Test_Files:
      declare
         use type  Ada.Command_Line.Exit_Status;
      begin

         For_Each_File_To_Delete:
         for D of File_Array loop

            if D.Passed then

               Ada.Directories.Delete_File (Name => D.Input_Filename);

               Ada.Directories.Delete_File (Name => D.Output_Filename);

            elsif Program_Exit_Status = Ada.Command_Line.Success then

               Program_Exit_Status := Ada.Command_Line.Failure;

            end if;

         end loop For_Each_File_To_Delete;

      end Delete_Test_Files;

   end Test_TFTP_File_Transfers;

   Ada.Command_Line.Set_Exit_Status (Code => Program_Exit_Status);

end Tester;
