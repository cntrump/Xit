import Cocoa

class RenameBranchPanelController: SheetController
{
  @IBOutlet weak var promptLabel: NSTextField!
  @IBOutlet weak var textField: NSTextField!
  @IBOutlet weak var acceptButton: NSButton!
  
  var branchName: String
  {
    get
    {
      return textField.stringValue
    }
    set
    {
      promptLabel.stringValue = "Rename branch \"\(newValue)\" to:"
      textField.stringValue = newValue
    }
  }
}

extension RenameBranchPanelController: NSTextFieldDelegate
{
  func controlTextDidChange(_ obj: Notification)
  {
    acceptButton.isEnabled = XTRefFormatter.isValidRefString(textField.stringValue)
  }
}
