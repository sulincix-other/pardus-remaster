build:
	: Please run make install

install:
	mkdir -p $(DESTDIR)/usr/bin/
	mkdir -p $(DESTDIR)/etc/
	mkdir -p $(DESTDIR)/usr/share/icons/
	mkdir -p $(DESTDIR)/usr/share/applications/
	mkdir -p $(DESTDIR)/usr/lib/pardus/remaster/
	install remaster.sh $(DESTDIR)/usr/bin/remaster
	install remaster.svg $(DESTDIR)/usr/share/icons/remaster.svg
	install remaster.desktop $(DESTDIR)/usr/share/applications/remaster.desktop
	install installer.sh $(DESTDIR)/usr/lib/pardus/remaster/install
	install main.py $(DESTDIR)/usr/lib/pardus/remaster/mani.py
	install remaster.conf $(DESTDIR)/etc/remaster.conf
