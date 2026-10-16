package identity

import "github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"

// PT-BR copy, calm and plain.

func msgVerify(to, link string) mail.Message {
	return mail.Message{To: to, TTL: verifyTTL, Subject: "Confirme seu e-mail na Telinha Segura", Body: "Olá!\n\n" +
		"Para confirmar este e-mail, abra o link abaixo. Ele vale por 24 horas.\n\n" + link + "\n\n" +
		"Se não foi você que criou a conta, pode ignorar esta mensagem."}
}

func msgSignUpExisting(to, appBaseURL string) mail.Message {
	return mail.Message{To: to, Subject: "Alguém tentou criar uma conta com seu e-mail", Body: "Olá!\n\n" +
		"Alguém tentou criar uma conta na Telinha Segura com este e-mail, que já tem uma conta.\n\n" +
		"Se foi você, é só entrar. Esqueceu a senha? Dá para criar uma nova aqui:\n" + appBaseURL + "/esqueci-a-senha\n\n" +
		"Se não foi você, nada muda na sua conta."}
}

func msgPasswordChanged(to, appBaseURL string) mail.Message {
	return mail.Message{To: to, Subject: "A senha da sua conta foi alterada", Body: "Olá!\n\n" +
		"A senha da sua conta na Telinha Segura acabou de ser alterada, e os outros aparelhos saíram da conta.\n\n" +
		"Se não foi você, crie uma nova senha agora:\n" + appBaseURL + "/esqueci-a-senha"}
}

func msgEmailInUse(to, appBaseURL string) mail.Message {
	return mail.Message{To: to, Subject: "Pediram para usar seu e-mail em outra conta", Body: "Olá!\n\n" +
		"Alguém pediu para trocar o e-mail de uma conta da Telinha Segura para este endereço, que já tem uma conta. Nada mudou.\n\n" +
		"Esqueceu a senha? " + appBaseURL + "/esqueci-a-senha"}
}

func msgEmailChangeVerify(to, link string) mail.Message {
	return mail.Message{To: to, TTL: verifyTTL, Subject: "Confirme seu novo e-mail na Telinha Segura", Body: "Olá!\n\n" +
		"Para passar a usar este e-mail na sua conta, abra o link abaixo. Ele vale por 24 horas.\n\n" + link + "\n\n" +
		"Se não foi você, pode ignorar esta mensagem."}
}

func msgEmailChanged(to, appBaseURL string) mail.Message {
	return mail.Message{To: to, Subject: "O e-mail da sua conta mudou", Body: "Olá!\n\n" +
		"O e-mail da sua conta na Telinha Segura foi trocado e este endereço não recebe mais as mensagens dela.\n\n" +
		"Se não foi você, fale com a gente pelo app: " + appBaseURL}
}

func msgReset(to, link string) mail.Message {
	return mail.Message{To: to, TTL: resetTTL, Subject: "Crie uma nova senha na Telinha Segura", Body: "Olá!\n\n" +
		"Para criar uma nova senha, abra o link abaixo. Ele vale por 30 minutos e funciona uma vez só.\n\n" + link + "\n\n" +
		"Se não foi você que pediu, pode ignorar esta mensagem: sua senha continua a mesma."}
}

func msgResetDone(to, appBaseURL string) mail.Message {
	return mail.Message{To: to, Subject: "Sua senha foi redefinida", Body: "Olá!\n\n" +
		"Sua senha na Telinha Segura foi redefinida e todos os aparelhos saíram da conta.\n\n" +
		"Se não foi você, peça uma nova senha agora: " + appBaseURL + "/esqueci-a-senha"}
}

func msgIdentityLinked(to, provider, appBaseURL string) mail.Message {
	return mail.Message{To: to, Subject: "Sua conta agora também entra com " + provider, Body: "Olá!\n\n" +
		"Sua conta na Telinha Segura foi conectada a uma conta " + provider + ". A partir de agora, dá para entrar por ela.\n\n" +
		"Se não foi você, crie uma nova senha agora: " + appBaseURL + "/esqueci-a-senha"}
}

// msgPasswordClearedAndLinked closes a clear_password link.
// It does not suggest a new password: one set by recovery would not
// undo the link.
func msgPasswordClearedAndLinked(to, provider, appBaseURL string) mail.Message {
	return mail.Message{To: to, Subject: "Sua conta agora entra com " + provider, Body: "Olá!\n\n" +
		"Sua conta na Telinha Segura foi conectada a uma conta " + provider + " e a senha foi removida. " +
		"Por segurança, todos os aparelhos saíram da conta.\n\n" +
		"A partir de agora, é só entrar com " + provider + ".\n\n" +
		"Se não foi você, fale com a gente pelo app: " + appBaseURL}
}
