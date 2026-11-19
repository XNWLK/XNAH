-- Stand-in world, home page part (helper H): a mail that arrived some days ago.

-- W.mailAgo(mail, days): the mail arrived `days` days ago (it has 30 - days days left, as auction house mails do)
function W.mailAgo(m, days)
	m.daysLeft = 30 - days
	return m
end
