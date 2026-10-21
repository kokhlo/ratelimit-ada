with Ada.Characters.Handling;
with Ada.Strings.Hash;

package body Rate_Limit is

   function Key_Hash (Key : String) return Ada.Containers.Hash_Type is
      Lower : String (Key'Range);
   begin
      for I in Key'Range loop
         Lower (I) := Ada.Characters.Handling.To_Lower (Key (I));
      end loop;
      return Ada.Strings.Hash (Lower);
   end Key_Hash;

   function Same_Key (Left, Right : String) return Boolean is
      use Ada.Characters.Handling;
   begin
      if Left'Length /= Right'Length then
         return False;
      end if;
      for I in 0 .. Left'Length - 1 loop
         if To_Lower (Left (Left'First + I)) /=
           To_Lower (Right (Right'First + I))
         then
            return False;
         end if;
      end loop;
      return True;
   end Same_Key;

end Rate_Limit;
