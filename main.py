import gi, sys, os
gi.require_version('Gtk', '3.0')
gi.require_version('Vte', '2.91')
from gi.repository import Gtk
from gi.repository import Vte
from gi.repository import GLib
fname = ""

# Select output file
dialog = Gtk.FileChooserDialog("Save file", None,
    Gtk.FileChooserAction.SAVE,
    (Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
    Gtk.STOCK_SAVE, Gtk.ResponseType.OK)
)

response = dialog.run()
if response == Gtk.ResponseType.OK:
    fname = dialog.get_filename()
elif response == Gtk.ResponseType.CANCEL:
    sys.exit(1)
dialog.destroy()

# Terminal
terminal = Vte.Terminal()
terminal.connect("child_exited",Gtk.main_quit)
terminal.spawn_sync(Vte.PtyFlags.DEFAULT, None, ["/bin/bash", "-c", "pkexec remaster '{}'".format(fname)], [], GLib.SpawnFlags.DO_NOT_REAP_CHILD, None, None)
# Window
win = Gtk.Window()
win.connect('delete-event', Gtk.main_quit)
win.add(terminal)
win.show_all()
Gtk.main()
