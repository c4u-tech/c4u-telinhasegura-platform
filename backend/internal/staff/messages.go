package staff

import "github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"

// PT-BR copy, calm and plain.
// Neither notice carries the staff reason.

func msgSuspended(to string) mail.Message {
	return mail.Message{To: to, Subject: "Sua conta na Telinha Segura foi suspensa", Body: "Olá!\n\n" +
		"Sua conta na Telinha Segura foi suspensa pela nossa equipe, e os aparelhos em que você estava conectado saíram dela.\n\n" +
		"Você ainda pode entrar no app para baixar uma cópia dos seus dados, excluir sua conta ou sair.\n\n" +
		"Se você acha que foi um engano, responda a este e-mail para pedir uma revisão."}
}

func msgReinstated(to string) mail.Message {
	return mail.Message{To: to, Subject: "Sua conta na Telinha Segura foi reativada", Body: "Olá!\n\n" +
		"A suspensão da sua conta na Telinha Segura terminou, e você já pode usar o app normalmente."}
}
