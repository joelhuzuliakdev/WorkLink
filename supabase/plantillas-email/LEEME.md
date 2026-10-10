# Emails de WorkLink (Supabase Auth)

Estas plantillas reemplazan los emails en inglés de Supabase. Se pegan a mano en
Supabase → Authentication → Emails → Templates (no se suben solas).

| Plantilla de Supabase   | Asunto                                   | Archivo                      |
|-------------------------|------------------------------------------|------------------------------|
| Confirm sign up         | Confirmá tu email en WorkLink            | 1-confirmar-cuenta.html      |
| Reset password          | Cambiá tu contraseña de WorkLink         | 2-recuperar-contrasena.html  |
| Change email address    | Confirmá el cambio de email en WorkLink  | 3-cambiar-email.html         |

Los enlaces van a /auth/confirm con `token_hash`: funcionan aunque el email se
abra en otro celular o computadora.

Para que los emails lleguen a cualquier persona hace falta un servidor de
correo propio (SMTP). Ver la guía de lanzamiento.
