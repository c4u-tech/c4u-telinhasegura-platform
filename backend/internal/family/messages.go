package family

import "github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"

// PT-BR copy, calm and plain. No
// message names a minor.

func msgInvitation(to, inviter, link string) mail.Message {
	return mail.Message{To: to, TTL: invitationTTL, Subject: "Você recebeu um convite para uma família na Telinha Segura", Body: "Olá!\n\n" +
		inviter + " convidou você para cuidar junto de uma família na Telinha Segura.\n\n" +
		"Para aceitar, abra o link abaixo. Ele vale por 7 dias e pede uma conta com este e-mail.\n\n" + link + "\n\n" +
		"Se você não esperava este convite, pode ignorar esta mensagem."}
}

func msgRemoved(to, appBaseURL string) mail.Message {
	return mail.Message{To: to, Subject: "Você não faz mais parte de uma família na Telinha Segura", Body: "Olá!\n\n" +
		"Quem administra a família tirou você dela. Sua conta continua ativa:\n" + appBaseURL}
}

func msgNowOwner(to, appBaseURL string) mail.Message {
	return mail.Message{To: to, Subject: "Agora você administra a família na Telinha Segura", Body: "Olá!\n\n" +
		"A administração da família passou para você. Agora você convida e remove responsáveis, e pode excluir a família:\n" + appBaseURL}
}

func msgNoLongerOwner(to, appBaseURL string) mail.Message {
	return mail.Message{To: to, Subject: "Você passou a administração da família", Body: "Olá!\n\n" +
		"Você passou a administração da família na Telinha Segura. Você continua como responsável:\n" + appBaseURL}
}

func msgFamilyDeleted(to, appBaseURL string) mail.Message {
	return mail.Message{To: to, Subject: "Uma família da qual você fazia parte foi excluída", Body: "Olá!\n\n" +
		"Quem administrava a família na Telinha Segura a excluiu, com os perfis das crianças. Sua conta continua ativa:\n" + appBaseURL}
}
