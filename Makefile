install:
	mkdir -p $(DESTDIR)/usr/bin/
	mkdir -p $(DESTDIR)/usr/share/icons/
	mkdir -p $(DESTDIR)/usr/share/applications/
	install remaster.sh $(DESTDIR)/usr/bin/remaster
	install remaster.svg $(DESTDIR)/usr/share/icons/remaster.svg
	install remaster.desktop $(DESTDIR)/usr/share/applications/remaster.desktop
