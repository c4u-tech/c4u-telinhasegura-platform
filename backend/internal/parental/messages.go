package parental

import (
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
)

// brasilia is UTC−3; Brazil has had no daylight saving since 2019, and a
// fixed zone needs no tzdata in the container.
var brasilia = time.FixedZone("BRT", -3*60*60)

// PT-BR copy, calm and plain. It names neither
// the PIN nor any email.
func msgPINChanged(to string, at time.Time, appBaseURL string) mail.Message {
	return mail.Message{To: to, Subject: "O PIN da família foi alterado", Body: "Olá!\n\n" +
		"O PIN da sua família na Telinha Segura foi definido ou alterado em " + at.In(brasilia).Format("02/01/2006 às 15:04") + ".\n\n" +
		"Se foi alguém da família, está tudo certo. Se você não reconhece a mudança, entre no app e defina um novo PIN:\n" + appBaseURL}
}
