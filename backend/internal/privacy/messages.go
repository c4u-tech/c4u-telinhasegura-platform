package privacy

import "github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"

// PT-BR copy, calm and plain. No
// message names a minor or holds a link.

func msgAccountDeleted(to string) mail.Message {
	return mail.Message{To: to, Subject: "Sua conta na Telinha Segura foi excluída", Body: "Olá!\n\n" +
		"Sua conta na Telinha Segura foi excluída, como você pediu. Apagamos seu acesso, suas sessões " +
		"e os vínculos com o Google ou a Apple.\n\n" +
		"Se quiser voltar um dia, é só criar uma conta nova."}
}
