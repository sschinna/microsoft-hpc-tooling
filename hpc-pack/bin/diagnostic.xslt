<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<xsl:output method="html"/>

	<xsl:template match="TestResult">
		<html>
		<head>
			<title> Test result for <xsl:value-of select="Name" /> </title>
			
			<script type="text/javascript">
				var plusbutton  = '<div class="inButton" style="margin:0px 0px 0px 5px; height:5px; width:3px;"></div>';
					plusbutton += '<div class="inButton" style="margin:0px 0px 0px 0px; height:3px; width:13px;"></div>';
					plusbutton += '<div class="inbutton" style="margin:0px 0px 0px 5px; height:5px; width:3px;"></div>';
				
				var minusbutton = '<div class="inButton" style="padding:0px; margin:7px 1px 5px 1px; height:3px; width:11px;"></div>';
				
				function writeMinusButton(p){
					document.write(minusbutton);
				}
				
				function writePlusButton(){
					document.write(plusbutton);
				}
				
				function togglevis(buttonname, divname){
					var vis = document.getElementById(divname).style.display;
								
					if(vis == '') {
						document.getElementById(divname).style.display = 'none';
						buttonname.innerHTML = plusbutton;
					} else if (vis == 'none') {
						document.getElementById(divname).style.display = '';
						buttonname.innerHTML = "";
						buttonname.innerHTML = minusbutton;
					}
				}
			</script>
			
			<style type="text/css">				
				body	{
					font-family:tahoma, "segoe ui", verdana, sans-serif;
					font-size:12px;
					color:#111111;
					padding:20px;
					margin:0px;
				}
				
				h1	{
					font-weight:normal;
					font-size:1.4em;
					padding:0px 0px 2px 4px;
					margin:0px;
					color:#333333;
				}
				
				h2	{
					font-size:1.3em;
					color:#333333;
					margin:20px 0px 0px 0px;
					font-weight:normal;
					padding:0px;
				}
				
				h3	{
					font-size:1.1em;
					color:#333333;
					margin:20px 0px 0px 0px;
					font-weight:normal;
					padding:0px;
				}
				
				h3 img	{
					border:0px;
					padding:0px;
					margin:0px 10px 0px 3px;
					cursor:hand;
					background-color:transparent;
				}
				
				h4	{
					font-size:1em;
					color:#555555;
					margin:8px 0px 3px 0px;
				}
				
				h5	{
					color:#666666;
					margin:0px;
					padding:0px;
					font-weight:normal;
					font-size:1em;
				}
				
				pre	{
					font-family:tahoma, "segoe ui", verdana, sans-serif;
					border:0px;
					margin:5px 0px 0px 0px;
					padding:0px;
				}
				
				hr	{
					margin:0px;
					padding:0px;
					color:#eeeeee;
				}

				ul	{
					margin:0px 20px;
				}

				ul li	{
					margin:3px 0px;
					color:#444444;
					font-size:1em;
				}
				
				a,
				a:link,
				a:visited,
				a:active	{
					color:#555555;
				}
				
				a:hover	{
					color:#111111;
				}
				
				/* Section headers */

				#header	{
					margin-bottom:15px;
					display:block;
					padding:0px;
				}	

				#header td	{
					padding:5px 10px;
					font-size:1em;
				}	
				
				#topresults	{
					padding:0px;
					margin:0px;
				}
				
				
				/* Colored Results */
				
				.detail	{
					vertical-align:middle;
					font-size:.8em;
					color:#666666;
					font-weight:normal;
					display:inline;
					margin:0px 0px 0px 10px;
				}
				
				#textgreen	{
					color:#22aa22;
				}	

				#textred	{
					color:#cc2222;
				}
				
				#textyellow	{
					color:#dd6600;
				}	
					
				#topresults #green	{
					background-color:#eeffee;
					color:#118811;
				}

				#topresults #red	{
					background-color:#ffeeee;
					color:#bb1111;
				}

				#topresults #yellow	{
					background-color:#ffffcc;
					color:#cc4400;
				}

				
				/* Table Grids */
				#grid	{
					border-top:1px solid #dddddd;
					border-left:1px solid #dddddd;
					padding:0px;
					margin:0px 0px 0px 5px;
					font-size:1em;
				}

				#grid td	{
					border-right:1px solid #dddddd;
					border-bottom:1px solid #dddddd;
					background-color:#ffffff;
					padding:7px;
					font-size:1em;
				}

				#grid #colheader	{
					background-color:#eeeeee;
					font-size:1em;
				}

				
				/* Summary Results Messages */
				#topresults h2,
				#topresults h3,
				.nodediv h2,
				.nodediv h3	{
					background-color:#eeeeee;
					color:#333333;
					padding:5px 8px;
					margin:2px;
					font-size:1.1em;
				}

				/* Expand Collapse divs */
				#nodediv,
				#detailsdiv,
				#otherdiv,
				.nodediv	{
					display:block;
					margin:0px 0px 0px 26px;
					font-size:1em;
				}

				#detailsdiv table,
				.nodediv table	{
					font-size:1em;
				}			
				
				#nodesdiv ul	{
					margin:0px 0px 0px 45px;
				}
				
				
				/* Buttons */
				.button	{
					padding:2px;
					border:1px solid #cccccc;
					float:left;
					margin:0px 8px 0px 0px;
					width:10px;
					background-color:#eeeeee;
					cursor:hand;
				}
				
				.inButton	{
					background-color:#888888;
					padding:0px;
					font-size:0px;
				}
			</style>
		
		</head>
		<body>
		
		<h1><xsl:value-of select="Name" /></h1>
		
		<!-- Show Test Summary Output -->
		<xsl:for-each select="StepResults/StepResult[@IsSummary = 'true']">
				
			<!-- Summary Header -->
			<div id="topresults">			
				<xsl:choose>
					<xsl:when test="Result = 'Failure'">
						<h2 id="red"> Test Result: Failure</h2>
					</xsl:when>
					<xsl:when test="Result = 'Failed To Run'">
						<h2 id="red"> Test Result: Failed to Run</h2>
					</xsl:when>
					<xsl:when test="Result = 'Success'">
						<h2 id="green"> Test Result: Success</h2>
					</xsl:when>
					<xsl:when test="Result = 'Warning'">
						<h2 id="yellow"> Test Result: Warning</h2>
					</xsl:when>
					<xsl:otherwise>
						<h2>Test Result: <xsl:value-of select="Result" /> </h2>
					</xsl:otherwise>
				</xsl:choose>
				
				<xsl:if test="Message != ''">
					<h3><pre>Message: <xsl:value-of select="Message" /></pre></h3>
				</xsl:if>
				
				<xsl:if test="ExceptionMessage != ''">
					<h3><pre>Exception message: <xsl:value-of select="ExceptionMessage" /></pre></h3>
				</xsl:if>			
			</div>
			
			<!-- Failed Nodes List -->
			<xsl:choose>
				<xsl:when test="FailedNodes = '' or count(FailedNodes/Node) = '0'">
					<h3>
						<div onclick="togglevis(this, 'nodesdiv');" class="button" >
							<script type="text/javascript">
								document.write(minusbutton);
							</script>
						</div>
						Failed nodes list 
						<p class="detail">(0)</p>
					</h3>
					<hr />
					<div id="nodesdiv">
						No nodes failed this test.
					</div>
				</xsl:when>
				<xsl:when test="count(FailedNodes/Node) &lt; '6'">
					<h3>
						<div onclick="togglevis(this, 'nodesdiv');" class="button" >
							<script type="text/javascript">
								document.write(minusbutton);
							</script>
						</div>
						Failed nodes list 
						<p class="detail">(<xsl:value-of select="count(FailedNodes/Node)"/>)</p>
					</h3>
					<hr />
					<div id="nodesdiv"><ul>		
						<xsl:for-each select="FailedNodes/Node">
							<li><a href="#jump{.}" title="Go to test results for {.}"><xsl:value-of select="." /></a></li>			
						</xsl:for-each>
					</ul></div>
				</xsl:when>
				<xsl:otherwise>
					<h3>
						<div onclick="togglevis(this, 'nodesdiv');" class="button" >
							<script type="text/javascript">
								document.write(plusbutton);
							</script>
						</div>
						Failed nodes list 
						<p class="detail">(<xsl:value-of select="count(FailedNodes/Node)"/>)</p>
					</h3>
					<hr />
					<div id="nodesdiv" style="display:none;"><ul>		
						<xsl:for-each select="FailedNodes/Node">
							<li><a href="#jump{.}" title="Go to test results for {.}"><xsl:value-of select="." /></a></li>			
						</xsl:for-each>
					</ul></div>
				</xsl:otherwise>
			</xsl:choose>
			
			<!-- Summary Tables -->
			<xsl:if test="Tables != ''">
				<h3>
					<div onclick="togglevis(this, 'detailsdiv');" class="button" >
						<script type="text/javascript">
							document.write(minusbutton);
						</script>
					</div>
					Test result details 
				</h3>
				<hr />
				<div id="detailsdiv">
					<xsl:for-each select="Tables/Table">
						<table border="0" cellpadding="0" cellspacing="0">
							<tr><td>
								<h4><xsl:value-of select="@Name" /> </h4>
							</td></tr>
							<xsl:if test="@Description != ''">
								<tr><td>
									<h5><xsl:value-of select="@Description" /></h5>
								</td></tr>
							</xsl:if>
							<tr><td height="8"> </td></tr>
							<tr><td>
								<table id="grid" border="0" cellpadding="5" cellspacing="0">
									<tr>
									<xsl:for-each select="Columns/Column">
										<td id="colheader"> <xsl:value-of select="." /> </td>
									</xsl:for-each>
									</tr>
									<xsl:for-each select="Rows/Row/Items">
									<tr>
										<xsl:for-each select="RowItem">
											<td><xsl:if test=".=''"><xsl:text>&#160;</xsl:text></xsl:if><xsl:value-of select="." /></td>
										</xsl:for-each>
									</tr>
									</xsl:for-each>
								</table>
							</td></tr>
						</table>
						<br />
					</xsl:for-each>
				</div>
			</xsl:if>

			<!-- Bullet Points -->
			<xsl:if test="BulletPoints != ''">		
				<h3>
					<div onclick="togglevis(this, 'otherdiv');" class="button" >
						<script type="text/javascript">
							document.write(minusbutton);
						</script>
					</div>
					Other information 
				</h3>
				<hr />
				<div id="otherdiv">
				<xsl:for-each select="BulletPoints/Information">
					<h4> <xsl:value-of select="Type" /> </h4>
					<ul>
					<xsl:for-each select="Message">
						<li> <xsl:value-of select="." /> </li>
					</xsl:for-each>
					</ul>
					<br />
				</xsl:for-each>
				</div>
			</xsl:if>
					
		</xsl:for-each>
		

		
		<!-- Show Nodes Output -->	
		<xsl:if test="StepResults/StepResult[@IsSummary = 'false'] != ''">
			<br />
			<div id="topresults"><h3>Test results by node</h3></div>
			<br />
		
			<xsl:for-each select="StepResults/StepResult[@IsSummary = 'false']">
				
				<!-- Node Header -->
				<a name="jump{@NodeName}" />
				<h3>
					<xsl:choose>
						<xsl:when test="Tables != '' or BulletPoints != '' or Message != '' or ExceptionMessage != '' ">
							<div onclick="togglevis(this, '{@NodeName}');" class="button" >
								<script type="text/javascript">
									document.write(plusbutton);
								</script>
							</div>
						</xsl:when>
						<xsl:otherwise>
							<div style="width:30px; border:0px; display:inline;" ></div>
						</xsl:otherwise>
					</xsl:choose>
					<xsl:choose>
						<xsl:when test="(Result = 'Failure') or (Result = 'Failed To Run')">
							<xsl:value-of select="@NodeName" />
							<p class="detail" id="textred">(<xsl:value-of select="Result"/>)</p>
						</xsl:when>
						<xsl:when test="Result = 'Success'">
							<xsl:value-of select="@NodeName" /> 
							<p class="detail" id="textgreen">(Success)</p>
						</xsl:when>
						<xsl:when test="Result = 'Warning'">
							<xsl:value-of select="@NodeName" /> 
							<p class="detail" id="textyellow">(Warning)</p>
						</xsl:when>
						<xsl:when test="Result = 'NoResult'">
							<xsl:value-of select="@NodeName" /> 
							<p class="detail">(No Result)</p>
						</xsl:when>
						<xsl:otherwise>
							<xsl:value-of select="@NodeName" /> 
							<p class="detail">(<xsl:value-of select="Result"/>)</p>
						</xsl:otherwise>
					</xsl:choose>
				</h3>
				<hr />
				
				<!-- Node Tables and Bullet Points-->
				<xsl:if test="Tables != '' or BulletPoints != '' or Message != '' or ExceptionMessage != '' " >
					<div class="nodediv" id="{@NodeName}" style="display:none;">
						<!-- Messages -->
						
						<xsl:if test="Message != ''">
							<h3><pre>Message: <xsl:value-of select="Message" /></pre></h3>
						</xsl:if>
						
						<xsl:if test="ExceptionMessage != ''">
							<h3><pre>Exception message: <xsl:value-of select="ExceptionMessage" /></pre></h3>
						</xsl:if>	
				
						<!-- Tables -->
						<xsl:if test="Tables != ''">
							<xsl:for-each select="Tables/Table">
								<table border="0" cellpadding="0" cellspacing="0">
									<tr><td>
										<h4><xsl:value-of select="@Name" /> </h4>
									</td></tr>
									<xsl:if test="@Description != ''">
										<tr><td>
											<h5><xsl:value-of select="@Description" /></h5>
										</td></tr>
									</xsl:if>
									<tr><td height="8"> </td></tr>
									<tr><td>
										<table id="grid" border="0" cellpadding="5" cellspacing="0">
											<tr>
											<xsl:for-each select="Columns/Column">
												<td id="colheader"> <xsl:value-of select="." /> </td>
											</xsl:for-each>
											</tr>
											<xsl:for-each select="Rows/Row/Items">
											<tr>
												<xsl:for-each select="RowItem">
													<td><xsl:if test=".=''"><xsl:text>&#160;</xsl:text></xsl:if><xsl:value-of select="." /></td>
												</xsl:for-each>
											</tr>
											</xsl:for-each>
										</table>
									</td></tr>
								</table>
								<br />
							</xsl:for-each>				
						</xsl:if>
				
						<!-- Bullet Points -->
						<xsl:if test="BulletPoints != ''">		
							<xsl:for-each select="BulletPoints/Information">
								<h4> <xsl:value-of select="Type" /> </h4>
								<ul>
								<xsl:for-each select="Message">
									<li> <xsl:value-of select="." /> </li>
								</xsl:for-each>
								</ul>
								<br />
							</xsl:for-each>
						</xsl:if>
						
						<br />
						<a href="#">back to top</a>
						<br /><br />
					</div>
				</xsl:if>
			</xsl:for-each>
		</xsl:if>
		
		</body>
		</html>
	</xsl:template>
</xsl:stylesheet>
